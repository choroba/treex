package Treex::Block::Clauses::CS::Compare;
use Moose;
use Treex::Core::Common;
use Treex::Core::Config;

extends 'Treex::Block::W2A::CS::ParseMSTAdapted';

sub print_verbose {
    my ($self, $message) = @_;

    log_info($message);
}

# For debug, parse whole sentence in a standard way.
# Return the same data structure as build_final_tree().
sub full_scale_parsing {
    my ($self, $a_root) = @_;

    my @a_nodes = $a_root->get_descendants({ordered => 1});
    my @words = map { $_->form } @a_nodes;
    my @tags = map { $_->tag } @a_nodes;

    my ($parents_rf, $afuns_rf) = $self->_parser->parse_sentence(\@words, undef, \@tags);

    my %data = ();
    foreach my $i ( 0 .. $#a_nodes) {
        my $node_id = $a_nodes[$i]->id;
        $data{$node_id}{parent} = $$parents_rf[$i];
        $data{$node_id}{afun} = $$afuns_rf[$i];
    }

    return %data;
}

sub chunk_parsing {
    my ($self, $a_root) = @_;

    # Call process_atree() from BaseChunkParser.
    $self->SUPER::process_atree($a_root);

    # Return the topology.
    return $self->get_parsing_data($a_root);
}

sub get_parsing_data {
    my ($self, $a_root) = @_;

    # Extract parsed data.
    my @a_nodes = $a_root->get_descendants({ordered => 1});

    my %data = ();
    foreach my $a_node (@a_nodes) {
        my $node_id = $a_node->id;
        $data{$node_id}{parent} = $a_node->get_parent->ord;
    }

    return %data;
}

sub process_atree {
    my ($self, $a_root) = @_;

    # Print parsing task ID.
    $self->print_verbose("");
    $self->print_verbose("================================================================================================");
    $self->print_verbose("CLAUSAL PARSING : \e[1;32m" . $a_root->id . "\e[m");
    $self->print_verbose("================================================================================================");
    $self->print_verbose("");

    # Print input sentence.
    $self->print_verbose("**************");
    $self->print_verbose("INPUT SENTENCE");
    $self->print_verbose("**************");
    $self->print_verbose("");
    $self->print_verbose("\e[1;33m" . join(" ", map {$_->form} $a_root->get_descendants({ordered => 1})) . "\e[m");
    $self->print_verbose("");

    # Baseline parsing obtain on both modes.
    my %gold = $self->get_parsing_data($a_root);
    my %mst = $self->full_scale_parsing($a_root);
    my %chunk = $self->chunk_parsing($a_root);

    # Debug.
    $self->print_verbose("");
    $self->print_verbose("Id                             | Form             | Ord | MST    | CHU    | GOL");
    $self->print_verbose("-------------------------------+------------------+-----+--------+--------+----");
    my @a_nodes = $a_root->get_descendants({ordered => 1});
    foreach my $node (@a_nodes) {
        my $node_id = $node->id;
        my $gold_parent = $gold{$node_id}{parent};
        my $mst_parent = $mst{$node_id}{parent};
        my $diff_mst = $gold_parent == $mst_parent ? " " : "x";
        my $chunk_parent = $chunk{$node_id}{parent};
        my $diff_chunk = $gold_parent == $chunk_parent ? " " : "x";

        $self->print_verbose(sprintf("%30s | %16s | %3d | %3d %2s | %3d %2s | %3d", $node_id, $node->form, $node->ord, $mst_parent, $diff_mst, $chunk_parent, $diff_chunk, $gold_parent));
    }
    $self->print_verbose("");
}

1;

__END__

=over

=item Treex::Block::Clauses::CS::Parse

Meta algorithm for parsing using Clausal Graphs by Vincent Kriz.
The parsing task on the whole sentence is split into several independent sub-tasks.
Individual parsing sub-tasks are solved by McDonald's MST parser adapted by Zdenek Zabokrtsky and Vaclav Novak.

=back

=cut

=head1 COPYRIGHT AND LICENSE

Copyright © 2016 by Vincent Kriz <kriz@ufal.mff.cuni.cz>

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
