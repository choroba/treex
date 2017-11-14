package Treex::Tool::Align::Utils;

use Moose;
use Treex::Core::Common;
use Data::Dumper;
use List::MoreUtils qw/any/;

extends 'Treex::Core::Block';

my %SIEVES_HASH = (
    self => \&access_via_self,
    eparents => \&access_via_eparents,
    siblings => \&access_via_siblings,
);

sub add_aligned_node {
    my ($node1, $node2, $type) = @_;
    #log_info "ALIGN ADD: " . $node2->id;
        
    # TODO should not call a private method of a different class
    my @old_types = $node1->_get_alignment_types($node2);
    my $type_defined = any {$_ eq $type} @old_types;
    if (!$type_defined) {
        #log_info "ADD_ALIGN: $type " . $node2->id;
        $node1->add_aligned_node($node2, $type);
    }

    #if ($node1->is_directed_aligned_to($node2, {rel_types => ['^'.$old_type.'$']})) {
    #    $node1->delete_aligned_node($node2, $old_type);
    #    $node1->add_aligned_node($node2, "$old_type $type");
    #}
    #else {
    #    $node2->delete_aligned_node($node1, $old_type);
    #    $node2->add_aligned_node($node1, "$old_type $type");
    #}
}

sub check_gold_aligns_from_to {
    my ($src_node, $trg_node, $rel_types) = @_;
    my ($gold_src_ali, $gold_src_types) = $src_node->get_undirected_aligned_nodes({
        language => $trg_node->language,
        selector => $trg_node->selector,
        rel_types => $rel_types });
    if (my @other = grep {$_ != $trg_node} @$gold_src_ali) {
        log_warn "A gold alignment link pointing to a different node in the same zone already exists for node: ".$src_node->get_address . " -> " . join ", ", map {$_->get_address} @other;
        log_warn "Original trg_node: ".$trg_node->get_address;
        log_warn "Align types: ".join ", ", @$gold_src_types;
    }
}


sub aligned_transitively {
    my ($nodes, $filters) = @_;

    my @level_aligned = @$nodes;

    my $filter;
    foreach my $filter (@$filters) {
        @level_aligned = map {my ($n, $t) = $_->get_undirected_aligned_nodes($filter); @$n;} @level_aligned;
    }
    return @level_aligned;
}

sub aligned_robust {
    my ($tnode, $align_filters, $sieves, $filters) = @_;

    my $errors = [];

    for (my $i = 0; $i < @$sieves; $i++) {
        my $sieve = $sieves->[$i];
        if (ref($sieve) ne "CODE") {
            $sieve = $SIEVES_HASH{$sieve};
        }
        my @aligned = $sieve->($tnode, $align_filters, $errors);
        if (@aligned) {
            my $filter = $filters->[$i];
            return (\@aligned, $errors) if (!defined $filter);
            my @filtered_align = $filter->(\@aligned, $tnode, $errors);
            #print STDERR "FILTER_" . $i . ": " . $filtered_align[0]->get_address . "\n" if (@filtered_align);
            return (\@filtered_align, $errors) if (@filtered_align);
        }
    }
    return (undef, $errors);
}

sub access_via_self {
    my ($tnode, $align_filters, $errors) = @_;
    my ($aligned_tnode) = aligned_transitively([$tnode], $align_filters);
    if (!defined $aligned_tnode) {
        push @$errors, "NO_CS_REF_TNODE";
        return;
    }
    return $aligned_tnode;
}

sub access_via_eparents {
    my ($tnode, $align_filters, $errors) = @_;

    my @epars = $tnode->get_eparents({or_topological => 1});
    my @aligned_pars = aligned_transitively(\@epars, $align_filters);
    if (!@aligned_pars) {
        push @$errors, "NO_ALIGNED_PARENT";
        return;
    }
    my @aligned_siblings = map {$_->get_echildren({or_topological => 1})} @aligned_pars;
    return @aligned_siblings;
}

sub access_via_siblings {
    my ($tnode, $align_filters, $errors) = @_;

    my @sibs = $tnode->get_siblings();
    if (!@sibs) {
        push @$errors, "NO_SIBLINGS";
        return;
    }
    my @aligned_sibs = aligned_transitively(\@sibs, $align_filters);
    if (!@aligned_sibs) {
        push @$errors, "NO_ALIGNED_SIBLINGS";
        return;
    }
    return @aligned_sibs;
}

1;

__END__

=head1 NAME

Treex::Tool::Align::Utils

=head1 SYNOPSIS

 use Treex::Tool::Align::Utils;

=head1 DESCRIPTION

Even though word-alignment is considered to be non-directional, Treex natively represents
alignment between two nodes as a directed link. This module offers a set of functions
that enables the user to ask for alignment link without bothering about what is the direction
of alignment links in the particular document.

=head1 FUNCTIONS

=over

=back

=head1 AUTHOR

Michal Novak <mnovak@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2014-15 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
