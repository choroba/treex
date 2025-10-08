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


package Treex::Tool::UMR::PDTV2PB::Transformation::Concept::Template;
use parent -norequire => 'Treex::Tool::UMR::PDTV2PB::Transformation';

sub run($self, $unode, $tnode, $) {
    my $template = $self->{template};
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

sub run($self, $unode, $tnode, $builder) {
    warn "DELETING";
    for my $ch ($unode->children) {
        $ch->set_parent($unode->parent);
        # TODO: New parent has the same arrow to me as the new edge.
    }
    $builder->safe_remove($unode, $unode->parent);
    return
}

package Treex::Tool::UMR::PDTV2PB::Transformation::List;
use parent -norequire => 'Treex::Tool::UMR::PDTV2PB::Transformation';
use Scalar::Util qw{ blessed };

sub run($self, $unode, $tnode, $builder) {
    for my $command (@{ $self->{list} }) {
        if (blessed($command)) {
            $command->run($unode, $tnode, $builder);
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

__PACKAGE__
