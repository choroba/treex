package Treex::Core::Node::Aligned;

use Moose::Role;

# with Moose >= 2.00, this must be present also in roles
use MooseX::SemiAffordanceAccessor;
use Treex::Core::Common;

my $DEFAULT_FILTER = { 
    directed => 1, 
};

sub get_aligned_nodes {
    my ($self, $filter) = @_;

    $filter //= { %{$self->default_filter} };
    
    # retrieve aligned nodes and its types outcoming links
    
    my ($aligned_to, $aligned_to_types) = $self->_get_direct_aligned_nodes();
    #log_info "ALITO: " . Dumper($aligned_to_types);
    #log_info "ALITOIDS: " . (join ",", map {$_->id} @$aligned_to);
    my @aligned = $aligned_to ? @$aligned_to : ();
    my @aligned_types = $aligned_to_types ? @$aligned_to_types : ();
    
    # retrieve aligned nodes and its types outcoming links
    
    my $directed = delete $filter->{directed};
    if (!$directed) {
        my @aligned_from = sort {$a->id cmp $b->id} $self->get_referencing_nodes('alignment');
        my %seen_ids = ();
        my @aligned_from_types = map {get_alignment_types($_, $self)} grep {!$seen_ids{$_->id}++} @aligned_from;
        #log_info "ALIFROM: " . Dumper(\@aligned_from_types);
        #log_info "ALIFROMIDS: " . (join ",", map {$_->id} @aligned_from);
        push @aligned, @aligned_from;
        push @aligned_types, @aligned_from_types;
    }

    # filter the retrieved nodes and links

    my ($final_nodes, $final_types) = (\@aligned, \@aligned_types);
    if (%$filter) {
        ($final_nodes, $final_types) = _edge_filter_out($final_nodes, $final_types, $filter);
        ($final_nodes, $final_types) = _node_filter_out($final_nodes, $final_types, $filter);
    }
  
    log_debug "[Tool::Align::Utils::get_aligned_nodes_by_filter]\tfiltered: " . (join " ", @$final_types), 1;
    return ($final_nodes, $final_types);
}

sub _node_filter_out {
    my ($nodes, $types, $filter) = @_;
    my $lang = $filter->{language};
    my $sel = $filter->{selector};

    my @idx = grep {
        (!defined $lang || ($lang eq $nodes->[$_]->language)) &&
        (!defined $sel || ($sel eq $nodes->[$_]->selector))
    } 0 .. $#$nodes;

    return ([@$nodes[@idx]], [@$types[@idx]]);
}

sub _value_of_type {
    my ($type, $type_list) = @_;
    my $i = 0;
    foreach my $type_re (@$type_list) {
        if ($type_re =~ /^!(.*)/) {
            return undef if ($type =~ /^$1$/);
        }
        else {
            return $i if ($type =~ /^$type_re$/);
        }
        $i++;
    }
    return undef;
}

sub _edge_filter_out {
    my ($nodes, $types, $filter) = @_;
    my $rel_types = $filter->{rel_types};
    return ($nodes, $types) if (!defined $rel_types);
    
    #log_info 'ALITYPES: ' . Dumper($types);
    my @values = map {_value_of_type($_, $rel_types)} @$types;
    #log_info 'ALITYPES: ' . Dumper(\@values);
    my @idx = grep { defined $values[$_] } 0 .. $#$nodes;
    @idx = sort {$values[$a] <=> $values[$b]} @idx;

    return ([@$nodes[@idx]], [@$types[@idx]]);
}

#sub get_aligned_nodes {
sub _get_direct_aligned_nodes {
    my ($self) = @_;
    my $links_rf = $self->get_attr('alignment');
    if ($links_rf) {
        my $document = $self->get_document;
        my @nodes    = map { $document->get_node_by_id( $_->{'counterpart.rf'} ) } @$links_rf;
        my @types    = map { $_->{'type'} } @$links_rf;
        return ( \@nodes, \@types );
    }
    return ( undef, undef );
}

#==============================================

sub get_aligned_nodes_by_tree {
    my ($self, $lang, $selector) = @_;
    my @nodes = ();
    my @types = ();
    my $links_rf = $self->get_attr('alignment');
    if ($links_rf) {
        my $document = $self->get_document;
        foreach my $l_rf (@{$links_rf}) {
            if ($l_rf->{'counterpart.rf'} =~ /^(a|t)_tree-$lang(_$selector)?-.+$/) {
                my $n = $document->get_node_by_id( $l_rf->{'counterpart.rf'} );
                my $t = $l_rf->{'type'};
                push @nodes, $n;
                push @types, $t;
            }
        }
        return ( \@nodes, \@types ) if     scalar(@nodes) > 0 ;    
    }
    return ( undef, undef );
}

sub get_aligned_nodes_of_type {
    my ( $self, $type_regex, $lang, $selector ) = @_;
    my @nodes;
    my ( $n_rf, $t_rf );
    if ((defined $lang) && (defined $selector)) {
        ( $n_rf, $t_rf ) = $self->get_aligned_nodes_by_tree($lang, $selector);
    }
    else {
        ( $n_rf, $t_rf ) = $self->get_aligned_nodes();    
    }    
    return if !$n_rf;
    my $iterator = List::MoreUtils::each_arrayref( $n_rf, $t_rf );
    while ( my ( $node, $type ) = $iterator->() ) {
        if ( $type =~ /$type_regex/ ) {
            push @nodes, $node;
        }
    }
    return @nodes;
}

sub is_aligned_to {
    my ( $self, $node, $type ) = @_;
    log_fatal 'Incorrect number of parameters' if @_ != 3;
    return ((any { $_ eq $node } $self->get_aligned_nodes_of_type( $type )) ? 1 : 0);
}

sub delete_aligned_node {
    my ( $self, $node, $type ) = @_;
    my $links_rf = $self->get_attr('alignment');
    my @links    = ();
    if ($links_rf) {
        @links = grep {
            $_->{'counterpart.rf'} ne $node->id
                || ( defined($type) && defined( $_->{'type'} ) && $_->{'type'} ne $type )
            }
            @$links_rf;
    }
    $self->set_attr( 'alignment', \@links );
    return;
}

sub add_aligned_node {
    my ( $self, $node, $type ) = @_;
    my $links_rf = $self->get_attr('alignment');
    my %new_link = ( 'counterpart.rf' => $node->id, 'type' => $type // ''); #/ so we have no undefs
    push( @$links_rf, \%new_link );
    $self->set_attr( 'alignment', $links_rf );
    return;
}

# remove invalid alignment links (leading to unindexed nodes)
sub update_aligned_nodes {
    my ($self)   = @_;
    my $doc      = $self->get_document();
    my $links_rf = $self->get_attr('alignment');
    my @new_links;

    foreach my $link ( @{$links_rf} ) {
        push @new_links, $link if ( $doc->id_is_indexed( $link->{'counterpart.rf'} ) );
    }
    $self->set_attr( 'alignment', \@new_links );
    return;
}
1;

__END__

=encoding utf-8

=head1 NAME

Treex::Core::Node::Aligned

=head1 DESCRIPTION

Moose role with methods to access alignment.

=head1 METHODS

=over

=item ($ali_nodes, $ali_types) = $node->get_aligned_nodes($filter)

This is the main getter method. It returns all nodes aligned to a specified node C<$node>,
and types of these alignment links as two list references -- C<$ali_nodes>, and C<$ali_types>,
respectively.

By the optional parameter C<$filter>, one may specify a filter to be applied to the nodes
and links. The filter is a hash reference, with the following possible keys:
 
C<language> - the language of the aligned nodes (e.g. C<en>)
C<selector> - the selector of the aligned nodes (e.g. C<src>)
C<directed> - return only the links originating from the C<$node> (possible values: C<0> and C<1>)
C<rel_types> - filter the alignment types. The value of this parameter must be a reference to
a list of regular expression strings. The expressions starting with the C<!> sign represent negative
filters. The actual link type is compared to these regexps one after another, skipping the rest
if the type matches a current regexp. If the type matches no regexps in the list, it is filtered out.
Therefore, negative rules should be at the beginning of the list, followed by at least one positive
rule. For instance, C<['a','b']> returns only links of type C<a> or C<b>. On the other hand, 
C<['!a','!b','.*']> returns everything except for C<a> and C<b>. The filter C<['!ab.*','a.*']>
accepts only the types starting with C<a>, except for those starting with C<ab>.

If no filter is specified, a default filter C<DEFAULT_FILTER> is used.

Both returned list references -- C<$ali_nodes> and C<$ali_types>, are always defined. If the
C<$node> has no alignment link that satisfies the filter constraints, a reference to an empty
list is returned.


=item $node->add_aligned_node($target, $type)

Aligns $target node to $node. The prior existence of the link is not checked.

=item my ($nodes_rf, $types_rf) = $node->get_aligned_nodes()

Returns an array containing two array references. The first array contains the nodes aligned to this node, the second array contains types of the links.

=item my @nodes = $node->get_aligned_nodes_of_type($regex_constraint_on_type)

Returns a list of nodes aligned to the $node by the specified alignment type.

=item $node->delete_aligned_node($target, $type)

All alignments of the $target to $node are deleted, if their types equal $type.

=item my $is_aligned = $node->is_aligned_to($target, $regex_constraint_on_type)

Returns 1 if the nodes are aligned, 0 otherwise.

=item $node->update_aligned_nodes()

Removes all alignment links leading to nodes which have been deleted.

=back

=head1 CONSTANTS

=over

=item DEFAULT_FILTER

A default filter is used, if no filter is specified for the methods that support it.
By default: { directed => 1 }

=back 

=head1 AUTHOR

Martin Popel <popel@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2011 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
