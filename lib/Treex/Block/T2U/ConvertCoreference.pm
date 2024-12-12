# -*- encoding: utf-8 -*-
package Treex::Block::T2U::ConvertCoreference;

use Moose;
use utf8;
use Treex::Core::Common;
use Treex::Tool::UMR::Common qw{ maybe_set };

use Graph::Directed;
use namespace::autoclean;


extends 'Treex::Core::Block';

has '+language' => ( required => 1 );

has '_tcoref_graph' => ( is => 'rw', isa => 'Graph::Directed' );

sub process_tnode {
    my ($self, $tnode) = @_;

    # my @tantes = map $_->get_coap_members, $tnode->get_coref_nodes;
    # $self->_tcoref_graph->add_edge($tnode->id, $_->id) for @tantes;
    $self->_tcoref_graph->add_edge($tnode->id, $_->id)
        for $tnode->get_coref_nodes({appos_aware => 0});
    return
}

before 'process_document' => sub {
    my ($self, $doc) = @_;
    my $tcoref_graph = Graph::Directed->new();
    $self->_set_tcoref_graph($tcoref_graph);
};

my $RELATIVE = '(?:který|jenž|jaký|co|kd[ye]|odkud|kudy|kam)';

# TODO: REMOVE!!!!!!!!!!
my $DEBUG_SORT = $ENV{BTRED_FAIL} ? sub { $a cmp $b } : sub { $b cmp $a };
my %SORT_NODETYPE = (ref => 0, entity => 1, event => 2);
after 'process_document' => sub {
    my ($self, $doc) = @_;

    my $tcoref_graph = $self->_tcoref_graph;

    my @tcoref_sorted = ();

    eval {
        @tcoref_sorted = $tcoref_graph->topological_sort();
    }
    or do {
        my @cycle_nodes = $tcoref_graph->find_a_cycle;
        while (@cycle_nodes) {
            log_warn("A coreference cycle found: " . join(" ", @cycle_nodes) . ". Skipping.");
            $tcoref_graph = $tcoref_graph->delete_cycle(@cycle_nodes);
            @cycle_nodes = $tcoref_graph->find_a_cycle;
        }
        @tcoref_sorted = $tcoref_graph->topological_sort();
    };

  TNODE:
    for my $tnode_id (@tcoref_sorted) {
        my $tnode = $doc->get_node_by_id($tnode_id);
        my ($unode) = $tnode->get_referencing_nodes('t.rf');
        next unless $unode;

        warn "T-U $tnode->{id} $unode->{id}";

        # First process the nodes from the same sentence.
        my @tantes
            = sort { $a->root == $tnode->root ? 0 : 1 }
              map $doc->get_node_by_id($_),
              $tcoref_graph->successors($tnode_id);
        warn join ' ', 'TANTE IDS', map $_->{id}, @tantes if 1 < @tantes;
      TANTE:
        for my $tante (@tantes) {
            my $tante_id = $tante->{id};
            my ($uante) = $tante->get_referencing_nodes('t.rf');

            warn "TNODE $tnode->{id} $unode->{nodetype} TANTE $tante_id $uante->{nodetype}";

            if ('INTF' eq $tante->functor) {
                log_warn("Removing with children: $tante_id")
                    if $uante->children;
                $uante->remove;
                for my $tante_ante (
                    $self->_tcoref_graph->successors($tante_id)
                ) {
                    $self->_tcoref_graph->delete_edge($tnode_id, $tante_id);
                    $self->_tcoref_graph->add_edge($tnode_id, $tante_ante);
                    redo TNODE
                }
                next TNODE
            }

            warn('DELETED'),
            next TANTE if grep $_->isa('Treex::Core::Node::Deleted'),
                          $unode, $uante;

            maybe_set($_, $unode, $tante) for qw( person number );

            # inter-sentential link
            if ($unode->root != $uante->root) {
                warn 'NODETYPES: ', $unode->{id}, '.', $unode->nodetype // '---', ' ', $uante->{id}, '.', $uante->nodetype // '---';
                if ($unode->nodetype ne 'ref') {
                    log_warn("set $tnode->{id} nodetype as $tante_id/$uante->{concept} " . $uante->nodetype);
                    $unode->add_coref($uante, 'same-' . $uante->nodetype);
                    $unode->set_nodetype($uante->nodetype);
                } else {
                    log_warn("$tnode->{id} is ref");
                    # $unode->add_coref($uante, 'same-' . $uante->nodetype);
                    # $unode->set_nodetype($uante->nodetype);
                }
            }
            # intra-sentential links with underspecified anaphors
            elsif ($tnode->t_lemma
                       =~ /^(?:#(?:Q?Cor|PersPron)|$RELATIVE)$/
                   && ! $tnode->children
            ) {
                log_warn("REL $tnode->{id}/$tnode->{t_lemma} $tante_id");
                log_warn("REL_M $tnode->{id}/$tnode->{t_lemma}")
                    if $tnode->is_member;
                $self->_same_sentence_coref(
                    $tnode, $unode, $uante, $tante_id, $doc);
                if ($tnode->t_lemma =~ /^$RELATIVE$/) {
                    $self->_relative_coref(
                        $tnode, $unode, $uante->id, $tante_id, $doc);
                }

            } else {
                $unode->add_coref($uante,
                                  'same-' . ($uante->nodetype eq 'event'
                                             ? 'event'
                                             : 'entity'));
                $unode->set_nodetype($uante->nodetype);
                log_warn("Unsolved coref $tnode_id $tante_id " . $uante->nodetype);
            }
        }
    }
};

sub _same_sentence_coref {
    my ($self, $tnode, $unode, $uante, $tante_id, $doc) = @_;
    for my $predecessor (
        $self->_tcoref_graph->predecessors($tnode->id)
    ) {
        $self->_tcoref_graph->delete_edge($predecessor, $tnode->id);
        $self->_tcoref_graph->add_edge($predecessor, $tante_id);

        my ($upred) = $doc->get_node_by_id($predecessor)
                    ->get_referencing_nodes('t.rf');
        if (my $coref = $upred->{coref}) {
            my @target_indices = (
                grep $coref->[$_]{'target_node.rf'} eq $unode->id,
                0 .. $coref->count - 1);
            warn "TIDXS: @target_indices";
            $coref->[$_]{'target_node.rf'} = $uante->id for @target_indices;
        } elsif ($upred->{'same_as.rf'}) {
            log_debug("SAME COREF $predecessor/$upred->{concept}, $tnode->{id}/$unode->{concept}", 1);
            $upred->make_referential($uante);
        } else {
            log_warn("CANNOT COREF $upred->{id}/$upred->{concept}, $unode->{id}/$unode->{concept}");
        }
    }
    if ($unode->children) {
        log_warn(sprintf "Cannot turn %s (%s) into REF because of CHILDREN",
                 map $_->id, $unode, $tnode);
    } elsif ('ref' eq $unode->{nodetype}) {
        my $parent = $unode->parent;
        my $ucopy = $parent->create_child;
        $ucopy->set_tnode($tnode);
        $ucopy->set_functor($unode->functor);
        $ucopy->make_referential($uante);
        warn "$tnode->{id} copied to reference $tante_id";
    } else {
        $unode->make_referential($uante);
        warn "$tnode->{id} made referential to $tante_id";
    }
}

# TODO: Coordinated verbs only if all of them share the "ktery" (see wsj2454.cz)
# $tnode is "ktery", $up is a RSTR verb, $gp is a coref antecedent.
sub _relative_coref {
    my ($self, $tnode, $unode, $uante_id, $tante_id, $doc) = @_;
    my $parent = $tnode->parent;

    my @eparents = $tnode->get_eparents;
    my @rstr_eparents = grep 'RSTR' eq $_->functor, @eparents;

    # There is a non-RSTR parent, we can't proceed.
    log_debug("Non RSTR parent $tnode->{id}", 1),
    return if @eparents != @rstr_eparents;

    log_warn("parent not same as eparents $tnode->{id}"),
    return if 'coap' ne $parent->nodetype
           && @eparents != 1
           && $eparents[0] != $parent;

    if ($parent->parent->id ne $tante_id
        && ($parent->_get_transitive_coap_root // {id => ""})->{id} ne $tante_id
    ) {
        log_debug("Cannot create *-of: $tnode->{id}/$tnode->{t_lemma} "
                  . "$parent->{id}/$parent->{t_lemma} "
                  . $tante_id, 1);
        return
    }

    my $uparent = $unode->parent;
    $uparent->set_functor($unode->functor . '-of');
    log_warn("Removing rel with children " . $tnode->id) if $unode->children;
    $unode->remove;
}

sub _rank {
    my ($node) = @_;
    my $rank = 0;
    $node = $node->parent, ++$rank while $node->parent;
    return $rank
}

sub _path_length {
    my ($node1, $node2) = @_;
    my @ranks = map _rank($_), $node1, $node2;
    my ($n1, $n2) = ($node1, $node2);
    my $cmp = $ranks[0] <=> $ranks[1];
    my $length = abs($ranks[0] - $ranks[1]);
    warn "LENGTH: $n1->{id} $n2->{id} = $length";
    if ($cmp) {
        my $move_up = {-1 => \$n2, 1 => \$n1}->{$cmp};
        $$move_up = $$move_up->parent for 1 .. $length;
    }
    while ($n1 != $n2) {
        $length += 2;
        $_ = $_->parent for $n1, $n2;
    }
    return $length
}

1;

=encoding utf-8

=head1 NAME

Treex::Block::T2U::ConvertCoreference

=head1 DESCRIPTION

Tecto-to-UMR converter of coreference relations.
It converts all coreferential links from the t- to the u-layer.
Three kinds of representation of tecto-like coreference are distinguished:
1. inversed participant role
2. reference to a concept within the same graph
3. document-level coreference annotation

=head1 AUTHOR

Michal Novák <mnovak@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2023 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
