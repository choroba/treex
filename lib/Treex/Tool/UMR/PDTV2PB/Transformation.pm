package Treex::Tool::UMR::PDTV2PB::Transformation;

=head1 NAME

Treex::Tool::UMR::PDTV2PB::Transformation

=cut

use warnings;
use strict;
use experimental qw( signatures );

sub new($class, $struct = {}) {
    bless $struct, $class
}

sub run($self, $unode, $tnode, $) {
    return $self->{value}
}

package Treex::Tool::UMR::PDTV2PB::Transformation::String;
use parent -norequire => 'Treex::Tool::UMR::PDTV2PB::Transformation';

sub run($self, $unode, $tnode, $) {
    return join "", @{ $self->{value} }
}

package Treex::Tool::UMR::PDTV2PB::Transformation::Concept::Template;
use parent -norequire => 'Treex::Tool::UMR::PDTV2PB::Transformation';

sub run($self, $unode, $tnode, $block) {
    my $template = $self->{template}->run($unode, $tnode, $block);
    my ($functor) = $template =~ /([A-Z]+[0-9]?)/;
    if (! $functor) {
        return $template
    }
    my @ch = grep $_->functor eq $functor, $tnode->get_echildren;
    if (1 == @ch) {
        my $tlemma = $ch[0]->t_lemma;
        $unode->set_concept($template =~ s/$functor/$tlemma/r);
        return
    }
    # E.g. cmpr9413_031.t##29.2 "mají návrhů a připomínek více" TODO
    die scalar @ch,
        " instead of 1 ${functor} at $tnode->{id} for a template $template."
}

package Treex::Tool::UMR::PDTV2PB::Transformation::Delete;
use parent -norequire => 'Treex::Tool::UMR::PDTV2PB::Transformation';

sub run($self, $unode, $tnode, $block) {
    warn "DELETING";
    for my $ch ($unode->children) {
        $ch->set_parent($unode->parent);
    }
    $block->safe_remove($unode, $unode->parent);
    return
}

package Treex::Tool::UMR::PDTV2PB::Transformation::List;
use parent -norequire => 'Treex::Tool::UMR::PDTV2PB::Transformation';
use Scalar::Util qw{ blessed };

sub run($self, $unode, $tnode, $block) {
    my @values;
    for my $command (@{ $self->{list} }) {
        if (blessed($command)) {
            push @values, $command->run($unode, $tnode, $block);
        } else {
            use Data::Dumper; warn Dumper COMMAND => $command;
        }
    }
    return @values
}

package Treex::Tool::UMR::PDTV2PB::Transformation::Add;
use parent -norequire => 'Treex::Tool::UMR::PDTV2PB::Transformation';

sub run($self, $unode, $tnode, $block) {
    die "$self->{target} not implemented" if 'echild' ne $self->{target};

    my $uch = $unode->create_child;
    $self->{$_}->run($uch, $tnode, $block) for qw( concept relation );
    return
}

package Treex::Tool::UMR::PDTV2PB::Transformation::Move;
use parent -norequire => 'Treex::Tool::UMR::PDTV2PB::Transformation';

sub run($self, $unode, $tnode, $block) {
    my @targets;
    if ('esibling' eq $self->{target}) {
        @targets = grep $_ != $tnode,
                   map $_->get_echildren,
                   $tnode->get_eparents;
    } else {
        die "$self->{target} no implemented for move!"
    }
    @targets = grep $_->functor eq $self->{functor}, @targets;
    die scalar(@targets) . " targets for move!" if @targets != 1;

    my @utargets = $targets[0]->get_referencing_nodes('t.rf');
    die scalar(@utargets) . " umr targets for move!" if @utargets != 1;

    $unode->set_parent($utargets[0]);
    $unode->set_relation($self->{relation});
    return
}

package Treex::Tool::UMR::PDTV2PB::Transformation::Error;
use parent -norequire => 'Treex::Tool::UMR::PDTV2PB::Transformation';

sub run($self, $unode, $tnode, $) {
    die 'Valency transformation error: ' . $unode->id . '/' . $tnode->id;
}

package Treex::Tool::UMR::PDTV2PB::Transformation::OK;
use parent -norequire => 'Treex::Tool::UMR::PDTV2PB::Transformation';

sub run($self, $unode, $tnode, $) {
    return ""
}

package Treex::Tool::UMR::PDTV2PB::Transformation::If;
use parent -norequire => 'Treex::Tool::UMR::PDTV2PB::Transformation';

sub run($self, $unode, $tnode, $block) {
    for my $cond (@{ $self->{cond} }) {
        return $self->{else}->run($unode, $tnode, $block)
            unless $cond->run($unode, $tnode, $block);
    }
    return $self->{then}->run($unode, $tnode, $block)
}

package Treex::Tool::UMR::PDTV2PB::Transformation::Condition;
use parent -norequire => 'Treex::Tool::UMR::PDTV2PB::Transformation';

sub run($self, $unode, $tnode, $) {
    my $attr = $self->{attr};
    if (! defined $self->{node}) {
        return grep $tnode->$attr eq $_, @{ $self->{values} }
    }

    if ('no-echild' eq $self->{node}) {
        my @children = grep {
            my $ch = $_;
            grep $ch->$attr eq  $_, @{ $self->{values} }
        } $tnode->get_echildren;
        return ! @children
    }

    my @candidates;
    if ('echild' eq $self->{node}) {
        @candidates = $tnode->get_echildren;
    } elsif ('esibling' eq $self->{node}) {
        @candidates = grep $_ ne $tnode,
                      map $_->get_echildren,
                      $tnode->get_eparents;
    }
    return grep {
        my $c = $_;
        grep $c->$attr eq $_, @{ $self->{values} }
    } @candidates
}

package Treex::Tool::UMR::PDTV2PB::Transformation::SetAttr;
use Scalar::Util qw{ blessed };
use parent -norequire => 'Treex::Tool::UMR::PDTV2PB::Transformation';

sub run($self, $unode, $tnode, $block) {
    my $setter = 'set_' . $self->{attr};
    my $node;
    if (my $search_node = $self->{node}) {
        # TODO: Implement properly!
        ($node) = map $_->get_referencing_nodes('t.rf'),
                  grep $_->functor eq $search_node,
                  $tnode->get_echildren;
    } else {
        $node = $unode;
    }
    my $value = $self->{value};
    $value = $value->run($unode, $tnode, $block) if blessed($value);
    $node->$setter($value);
    return
}

__PACKAGE__
