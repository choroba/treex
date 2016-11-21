package Treex::Block::Clauses::CS::GoldClauseChart;

use Moose;
use Treex::Core::Common;
use Treex::Core::Config;

extends 'Treex::Core::Block';

has 'verbose' => (
    is       => 'ro',
    isa      => 'Int',
    default  => 0
);

sub print_cg {
    my ($self, $a_root) = @_;

    my @a_nodes = $a_root->get_descendants({ordered => 1});
    my $cg = join("", (map {$_->{CG}} @a_nodes));
    $cg =~ s/(B+)/\e[1;31m$1\e[m/g;

    print STDERR sprintf("%30s | %s\n", $a_root->id, $cg);
}

# Define a clause chart annotation for the given node.
# When there are antecedents in the dependency tree,
# require a sorted list of antecedents in the @path.
# Recursively call itself on all node's children.
sub set_cg {
    my ($self, $node, @path) = @_;
    my $clause_number = $node->clause_number;

    if (!defined($clause_number)) {
        log_warn(sprintf("Undefined clause_number for node ('%s', '%s', '%s')", $node->id, $node->form, $node->tag));
        $clause_number = 0;
    }

    # Subordinate conjunction do not start the new clause,
    # instead they become the part of boundary.
    if (!scalar(grep(/^$clause_number$/, @path)) and
        $node->tag =~ /^J,/) {
        $clause_number = 0;
    }

    # Set CG to the node
    if ($clause_number == 0) {
        $node->{CG} = 'B';
        $node->{wild}{CG} = 'B';
        $node->serialize_wild();
    }
    else {
        if (!scalar(grep(/^$clause_number$/, @path))) {
            push(@path, $clause_number);
        }

        $node->{CG} = scalar(@path) - 1;
        $node->{wild}{CG} = scalar(@path) - 1;
        $node->serialize_wild();
    }

    # Call set_cg recursively to node children.
    foreach my $child ($node->get_children()) {
        $self->set_cg($child, @path);
    }
}

# When one of the quote in quote-pair is in the clause and another is not,
# put them into the same clause.
sub check_pair_punctuaction {
    my ($self, $a_root) = @_;

    my @a_nodes = $a_root->get_descendants({ordered => 1});
    for (my $i = 0; $i < scalar(@a_nodes); $i++) {
        my $node = $a_nodes[$i];
        if ($node->form =~ /^"|\)$/ and $node->{CG} eq 'B') {
            # print STDERR "$i: - parenthesis with B: " . $node->id . "\n";
            for (my $j = $i - 1; $j >= 0; $j--) {
                if ($a_nodes[$j]->form =~ /^"|\($/ and $a_nodes[$j]->{CG} =~ /^\d+$/) {
                    # print STDERR "   - parenthesis with " . $a_nodes[$j]->{CG} . ": " . $a_nodes[$j]->id . "\n";
                    $node->{CG} = $a_nodes[$j]->{CG};
                    $node->{wild}{CG} = $a_nodes[$j]->{CG};
                    $node->serialize_wild();
                    last;
                }
            }
        }
    }
}

# Subordinate conjunction on the beginning of the clause is the boundary.
sub check_subordinate_conjunction {
    my ($self, $a_root) = @_;

    my @a_nodes = $a_root->get_descendants({ordered => 1});
    for (my $i = 0; $i < scalar(@a_nodes) - 1; $i++) {
        my $current_node = $a_nodes[$i];
        my $next_node = $a_nodes[$i + 1];
        if ($current_node->{CG} eq 'B' and
            $next_node->tag =~ /^J,/) {
            $next_node->{CG} = 'B';
            $next_node->{wild}{CG} = 'B';
            $next_node->serialize_wild();
        }
    }
}

# If token with lemma 'který' is immediately after boundary token,
# make it a boundary as well.
sub check_relative_pronoun {
    my ($self, $a_root) = @_;

    my @a_nodes = $a_root->get_descendants({ordered => 1});
    for (my $i = 0; $i < scalar(@a_nodes) - 1; $i++) {
        my $current_node = $a_nodes[$i];
        my $next_node = $a_nodes[$i + 1];
        if ($current_node->{CG} eq 'B' and
            $next_node->lemma =~ /^který$/) {
            $next_node->{CG} = 'B';
            $next_node->{wild}{CG} = 'B';
            $next_node->serialize_wild();
        }
    }
}

# Generic method will call automatically by Treex for each a-tree.
# Process dependency tree and obtain the clause chart.
# Write clause chart annotation to each node.
sub process_atree {
    my ($self, $a_root) = @_;

    if ($self->verbose > 0) {
        log_info("Processing root $a_root");
    }

    # Obtain a clause chart annotation for each node.
    foreach my $child ($a_root->get_children()) {
        $self->set_cg($child, ());
    }

    # Print raw clause chart before applying correction methods.
    if ($self->verbose > 0) {
        $self->print_cg($a_root);
    }

    # Apply different correction methods to get better Clause Chart.
    $self->check_pair_punctuaction($a_root);
    $self->check_subordinate_conjunction($a_root);
    $self->check_relative_pronoun($a_root);

    # Print final Clause Chart.
    if ($self->verbose > 0) {
        $self->print_cg($a_root);
    }
}

1;

__END__

=over

=item Treex::Block::Clauses::CS::GoldClauseChart

Obtain a gold-standard Clause Chart from the given dependency tree
with the clause segmentation annotation (http://ufal.mff.cuni.cz/pdt3.0/documentation#__RefHeading__42_1200879062).
The clause segmentation annotation is available in the PDT 3.0 but it is available for all
gold-standard dependency trees using block A2A::CS::DetectClauses.

A final clause chart is then stored partially for each node in the attribute 'CG'.

=back

=cut

=head1 COPYRIGHT AND LICENSE

Copyright © 2016 by Vincent Kriz <kriz@ufal.mff.cuni.cz>

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
