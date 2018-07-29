package Treex::Block::CLTT::RemoveNumbering;

use Moose;
use Treex::Core::Common;
extends 'Treex::Core::Block';


sub _remove_node {
    my ($self, $node) = @_;

    my @children = $node->children();
    my $has_children = scalar(@children) ? 1 : 0;

    log_info(sprintf('%10s | %d | %s', $node->form, $has_children, $node->id));

    if (not $has_children) {
        $node->remove;
    }
}

sub process_document {
    my ($self, $document) = @_;
    my $sentence_id = 0;

    for my $b ($document->get_bundles) {
        for my $z ($b->get_all_zones) {
            for my $a_root ($z->get_all_trees) {
                my @a_nodes = $a_root->get_descendants({ordered => 1});
                foreach my $node (@a_nodes) {
                    my $form = $node->form;
                    my $tag = $node->tag;

                    if ($form =~ /^\(\d+\)$/ or
                        $form =~ /^[a-z]\)$/) {
                        $self->_remove_node($node);
                    }
                    elsif ($tag =~ /Z:/ and $node->parent == $a_root) {
                        $self->_remove_node($node);
                    }
                }
            }
        }
    }
}

1;
