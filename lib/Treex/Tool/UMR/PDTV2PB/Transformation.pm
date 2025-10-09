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
        $unode->set_concept($template);
        return
    }
    my @ch = grep $_->functor eq $functor, $tnode->get_echildren;
    if (1 == @ch) {
        my $tlemma = $ch[0]->t_lemma;
        $unode->set_concept($template =~ s/$functor/$tlemma/r);
        return
    }
    die scalar @ch, " instead of 1 ${functor} for a template $template."
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
    for my $command (@{ $self->{list} }) {
        if (blessed($command)) {
            $command->run($unode, $tnode, $block);
        } else {
            use Data::Dumper; warn Dumper COMMAND => $command;
        }
    }
    return
}

package Treex::Tool::UMR::PDTV2PB::Transformation::Error;
use parent -norequire => 'Treex::Tool::UMR::PDTV2PB::Transformation';

sub run($self, $unode, $tnode, $) {
    die 'Valency transformation error: ' . $unode->id . '/' . $tnode->id;
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
    return grep $tnode->$attr eq $_, @{ $self->{values} }
}

package Treex::Tool::UMR::PDTV2PB::Transformation::SetAttr;
use parent -norequire => 'Treex::Tool::UMR::PDTV2PB::Transformation';

sub run($self, $unode, $tnode, $) {
    my $setter = 'set_' . $self->{attr};
    $unode->$setter($self->{value});
    return
}

__PACKAGE__
