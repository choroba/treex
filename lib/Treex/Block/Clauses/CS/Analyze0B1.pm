package Treex::Block::Clauses::CS::Analyze0B1;

use Moose;
use Treex::Core::Common;
use Treex::Block::Clauses::CS::Parse;

extends 'Treex::Core::Block';

has 'clause_chart_threshold' => (
    is       => 'ro',
    isa      => 'Num',
    default  => 0
);

sub process_bundle {
    my ($self, $bundle) = @_;

    # Gold-standard.
    my $ref_zone = $bundle->get_zone($self->language, $self->selector);
    my %nodes = ();
    my $a_root = $ref_zone->get_atree;
    foreach my $node ($ref_zone->get_atree->get_descendants({ordered => 1})) {
        $nodes{$node->id} = "";
    }

    # Clause chart
    my $clause_chart = Treex::Block::Clauses::CS::Parse::get_clause_chart(undef, $ref_zone->get_atree);
    if ($clause_chart ne '0B1') {
        return;
    }

    # Extract lexicalized boundary.
    my $clause_structure = Treex::Block::Clauses::CS::Parse::init_clause_structure(undef, $ref_zone->get_atree);
    my @boundary_nodes = ();
    my $ktery_node = undef;
    my $subordinated_clause_root = undef;
    my $lexicalized_boundary = '';
    foreach my $block (@$clause_structure) {
        if ($block->{type} eq 'boundary') {
            $lexicalized_boundary = join('_', map {$_->lemma} @{$block->{nodes}});
            last;
        }
    }
    foreach my $block (@$clause_structure) {
        if ($block->{type} eq 'boundary') {
            foreach my $node (@{$block->{nodes}}) {
                $nodes{$node->id} = 'boundary';
                if ($node->lemma eq 'který') {
                    $ktery_node = $node;
                }
            }
        }
        elsif ($block->{deep} =~ /^\d+$/ and $block->{deep} == 1) {
            my @clause_nodes = map { $_->ord } @{$block->{nodes}};
            foreach my $node (@{$block->{nodes}}) {
                my $node_parent = $node->parent->ord;
                if (scalar(grep(/^$node_parent$/, @clause_nodes)) == 0) {
                    # $nodes{$node->id} = 'root';
                    $nodes{$node->parent->id} = 'root';
                    $subordinated_clause_root = $node->parent;
                }
            }
        }
    }

    if ($lexicalized_boundary ne ",_který") {
        return;
    }

    print "\n\n\n";
    print "\n----------------------------------------------------------\n\n\n\n";
    printf("[ %s ] [ %s ]", $a_root->id, $lexicalized_boundary);
    print "\n\n";


    my $tag1 = $subordinated_clause_root->tag;
    my $tag2 = $ktery_node->tag;
    $self->{stats}{pos}{substr($tag1, 1, 1)} += 1;
    $self->{stats}{gender}{sprintf("%s -> %s", substr($tag1, 2, 1), substr($tag2, 2, 1))} += 1;
    $self->{stats}{number}{sprintf("%s -> %s", substr($tag1, 3, 1), substr($tag2, 3, 1))} += 1;
    print "\n";

    # Rule-based approach to find the root of the subordinated clause in the 0-clause.
    my @candidates = reverse @{$$clause_structure[0]->{nodes}};
    my $identified_root = undef;
    foreach my $candidate (@candidates) {
        if (match_morphology($candidate, $ktery_node)) {
            while (42) {
                my $candidate_parent = $candidate->parent;
                if (!(match_morphology($candidate_parent, $ktery_node))) {
                    last;
                }
                else {
                    $candidate = $candidate_parent;
                }
            }
            $identified_root = $candidate;
            last;
        }
    }

    if ($identified_root) {
        $nodes{$identified_root->id} = 'detected';
    }

    print "\n\n";

    # Print whole sentence.
    # Highlight the root for C2 and the boundary.
    foreach my $node ($ref_zone->get_atree->get_descendants({ordered => 1})) {
        print "\t";

        if ($nodes{$node->id} eq 'root') {
            print "\e[1;31m"
        }
        elsif ($nodes{$node->id} eq 'detected') {
            print "\e[1;38m"
        }
        elsif ($nodes{$node->id} eq 'boundary') {
            print "\e[1;34m"
        }

        printf("%2d | %20s | %s | %5s | %2d", $node->ord, $node->form, $node->tag, $node->afun, $node->parent->ord);
        print "\e[m";
        print "\n";
    }

    print "\n";

    $self->{stats}{sentences} += 1;
    if ($identified_root == $subordinated_clause_root) {
        print "\tCorrect\n";
        $self->{stats}{correct} += 1;
    }

    print "\n";
    print "\n";
}

sub match_morphology {
    my ($candidate, $ktery_node) = @_;

    if (substr($candidate->tag, 1, 1) ne 'N') {
        return 0;
    }

    if (!(match_number(substr($candidate->tag, 3, 1), substr($ktery_node->tag, 3, 1)))) {
        return 0;
    }

    # if (!(match_gender(substr($candidate->tag, 2, 1), substr($ktery_node->tag, 2, 1)))) {
    #     return 0;
    # }

    return 1;
}

sub match_number {
    my ($tag1, $tag2) = @_;
    print "\tmatching number : $tag1 vs. $tag2\n";

    if ($tag1 eq 'X' or $tag1 eq '-' or $tag2 eq 'X' or $tag2 eq '-') {
        return 1
    }

    if ($tag1 eq $tag2) {
        return 1
    }

    return 0
}

sub match_gender {
    my ($tag1, $tag2) = @_;
    print "\tmatching gender : $tag1 vs. $tag2\n";

    if ($tag1 eq 'X' or $tag1 eq '-' or $tag2 eq 'X' or $tag2 eq '-') {
        return 1
    }

    if ($tag1 eq $tag2) {
        return 1
    }

    if ($tag1 eq 'F' and $tag2 =~ /[HQT]/) {
        return 1
    }

    if ($tag1 eq 'H' and $tag2 =~ /[FNQT]/) {
        return 1
    }

    if ($tag1 eq 'I' and $tag2 =~ /[TYZ]/) {
        return 1
    }

    if ($tag1 eq 'M' and $tag2 =~ /[YZ]/) {
        return 1
    }

    if ($tag1 eq 'N' and $tag2 =~ /[HQZ]/) {
        return 1
    }

    if ($tag1 eq 'Q' and $tag2 =~ /[FNHTZ]/) {
        return 1
    }

    if ($tag1 eq 'T' and $tag2 =~ /[FHIQY]/) {
        return 1
    }

    if ($tag1 eq 'Y' and $tag2 =~ /[IMZT]/) {
        return 1
    }

    if ($tag1 eq 'Z' and $tag2 =~ /[IMNQY]/) {
        return 1
    }

    return 0
}

sub process_end {
    my ($self) = @_;

    foreach my $stats ('gender', 'number', 'pos') {
        print "\n\n\n";
        print "*** $stats ***";
        print "\n\n\n";
        foreach my $test_case (keys %{$self->{stats}{$stats}}) {
            printf("%20s | %3d\n", $test_case, $self->{stats}{$stats}{$test_case});
        }
    }

    print "\n\n\n";
    print "sentences : " . $self->{stats}{sentences} . "\n";
    print "correct   : " . $self->{stats}{correct} . "\n";
}


1;

=over

=item Treex::Block::Clauses::CS::Eval

Evaluation of the dependency parsing, especially for parsing meta-algorithm by Kriz and Hladka (2016).
It takes selected zone as a gold-standard and calculates statistics for all other zones against this gold-standard.
Using option different_clasues=1 it reports UAS for all different clause structures.

=back

=cut

=head1 COPYRIGHT AND LICENSE

Copyright © 2016 by Vincent Kriz <kriz@ufal.mff.cuni.cz>

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
