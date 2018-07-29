package Treex::Block::CLTT::PrintPlaintext;

use Moose;
use Treex::Core::Common;
extends 'Treex::Core::Block';

has retokenization => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    default       => 0
);

sub process_document {
    my ($self, $document) = @_;
    my $sentence_id = 0;

    for my $b ($document->get_bundles) {
        for my $z ($b->get_all_zones) {
            for my $a_root ($z->get_all_trees) {
                my @a_nodes = $a_root->get_descendants({ordered => 1});

                foreach my $node (@a_nodes) {
                    my $form = $node->form;
                    if ($self->retokenization) {
                        $form =~ s/\s+/_/g;
                    }
                    print $form;
                    if ($self->retokenization) {
                        print ' ';
                    }
                    else {
                        if (!$node->no_space_after) {
                            print ' '
                        }
                    }
                }

                print "\n";
            }
        }
    }
}

1;
