package Treex::Block::CLTT::Multiplicate;

## Vincent Kriz, 2018
## Complex sentence multiplication.

use Moose;
use Treex::Core::Common;

extends 'Treex::Core::Block';

sub _get_document_id {
    my ($self, $node) = @_;

    if ($node->id =~ /document([^-]+)/) {
        return $1
    }

    return undef

}

sub _get_sentence_id {
    my ($self, $node) = @_;

    if ($node->id =~ /sentence(\d+)/) {
        return $1
    }

    return undef

}

sub _get_section_id {
    my ($self, $node) = @_;

    if ($node->id =~ /-section(\d+)/) {
        return $1
    }

    return undef
}

sub _get_subsection_id {
    my ($self, $node) = @_;

    if ($node->id =~ /-subsection(\d+)/) {
        return $1
    }

    return undef
}

sub _get_node_id {
    my ($self, $node) = @_;

    if ($node->id =~ /node(\d+)/) {
        return $1
    }

    return undef
}

sub _get_original_node_id {
    my ($self, $node) = @_;

    if ($node->id =~ /(section\d+(-subsection\d+)?-node\d+)$/) {
        return $1;
    }

    return undef;
}

sub _is_complex_sentence {
    my ($self, $aroot) = @_;

    my @children = $aroot->get_descendants();
    foreach my $child (@children) {
        if ($self->_get_section_id($child)) {
            return 1
        }
    }

    return 0
}

# Return a list of existing sections (other than 0).
sub _get_sections {
    my ($self, $aroot) = @_;
    my %different_sections = ();

    my @children = $aroot->get_descendants();
    foreach my $child (@children) {
        my $section = $self->_get_section_id($child);
        if ($section == 0) {
            next;
        }
        $different_sections{$section} = 1;
    }

    return sort(keys %different_sections);
}

# Return a list of existing subsections (other than 0).
sub _get_subsections {
    my ($self, $aroot, $section) = @_;
    my %different_subsections = ();

    my @children = $aroot->get_descendants();
    foreach my $child (@children) {
        my $child_section = $self->_get_section_id($child);
        if ($child_section != $section) {
            next;
        }

        my $subsection = $self->_get_subsection_id($child);
        if (not $subsection) {
            next;
        }
        if ($subsection == 0) {
            next;
        }
        $different_subsections{$subsection} = 1;
    }

    return sort(keys %different_subsections);
}

# Return the root nodes of the given section.
sub _get_section_roots {
    my ($self, $aroot, $section) = @_;
    my @root_nodes = ();

    my @candidate_nodes = $aroot->get_descendants();
    foreach my $node (@candidate_nodes) {
        if ($section == $self->_get_section_id($node)) {
            if (defined($self->_get_section_id($node->parent)) and $section == $self->_get_section_id($node->parent)) {
                next;
            }
            else {
                push(@root_nodes, $node);
            }
        }
    }

    return @root_nodes
}

# Return the root nodes of the given section.
sub _get_subsection_roots {
    my ($self, $aroot, $section, $subsection) = @_;
    my @root_nodes = ();

    my @candidate_nodes = $aroot->get_descendants();
    foreach my $node (@candidate_nodes) {
        if ($section == $self->_get_section_id($node)) {
            if ($subsection == $self->_get_subsection_id($node)) {
                if (defined($self->_get_subsection_id($node->parent)) and $subsection == $self->_get_subsection_id($node->parent)) {
                    next;
                }
                else {
                    push(@root_nodes, $node);
                }
            }
        }
    }

    return @root_nodes
}

# My own copy tree method with my own identifiers.
sub copy_atree {
    my ($self, $document, $sentence, $section, $subsection, $source, $target) = @_;

    $source->copy_attributes($target);
    my @source_children = $source->get_children( { ordered => 1 } );
    foreach my $source_child (@source_children) {
        my $source_child_original_id = $self->_get_original_node_id($source_child);
        my $target_child_id = sprintf("a-document%s-sentence%d-multiplication%d.%d-%s", $document, $sentence, $section, $subsection, $source_child_original_id);

        my $target_child = $target->create_child();
        $target_child->set_id($target_child_id);

        $self->copy_atree($document, $sentence, $section, $subsection, $source_child, $target_child);
    }

    return;
}

# Return a list of multi
sub multiplicate_complex_sentence {
    my ($self, $document, $bundle, $aroot) = @_;
    log_info("");
    log_info(sprintf("Splitting complex sentence: %s", $aroot->id));

    my @section0_roots = $self->_get_section_roots($aroot, 0);
    log_info(sprintf(" +-> section0 root nodes = %s", join(", ", map { $_->id } @section0_roots)));

    #
    # PREPROCESSING
    #

    # Let's try to set parent to be a root node for the section0 roots.
    foreach my $section0_root (@section0_roots) {
        $section0_root->set_parent($aroot);
    }

    my @sections = $self->_get_sections($aroot);
    foreach my $section (@sections) {
        my @section_roots = $self->_get_section_roots($aroot, $section);
        my @subsections = $self->_get_subsections($aroot, $section);

        log_info(" | ");
        log_info(sprintf(" +- Processing section %d", $section));
        log_info(sprintf(" |   +-> root nodes = %s", join(", ", map { $_->id } @section_roots)));

        if (scalar(@subsections)) {
            foreach my $subsection (0, @subsections) {
                my @subsection_roots = $self->_get_subsection_roots($aroot, $section, $subsection);

                log_info(" |   | ");
                log_info(sprintf(" |   +- Processing subsection %d", $subsection));
                log_info(sprintf(" |   |   +-> root nodes = %s", join(", ", map { $_->id } @subsection_roots)));

                foreach my $subsection_root (@subsection_roots) {
                    $subsection_root->set_parent($aroot);
                }
            }
        }
        else {
            foreach my $section_root (@section_roots) {
                $section_root->set_parent($aroot);
            }
        }
    }

    #
    # MULTIPLICATION
    #

    foreach my $section (sort @sections) {
        my @section_roots = $self->_get_section_roots($aroot, $section);

        my @subsections = $self->_get_subsections($aroot, $section);
        if (scalar(@subsections)) {
            my @subsection0_roots = $self->_get_subsection_roots($aroot, $section, 0);
            foreach my $subsection (sort @subsections) {
                my $new_bundle = $document->create_bundle({'after' => $bundle, 'id' => sprintf("%s-%s-%s", $bundle->id, $section, $subsection)});
                my $new_tree = $new_bundle->create_tree("cs", "a", "cltt");

                my @subsection_roots = $self->_get_subsection_roots($aroot, $section, $subsection);
                foreach my $node (@section0_roots, @subsection0_roots, @subsection_roots) {
                    my $document_id = $self->_get_document_id($node);
                    my $sentence_id = $self->_get_sentence_id($node);
                    my $node_original_id = $self->_get_original_node_id($node);
                    my $new_node_id = sprintf("a-document%s-sentence%d-multiplication%d.%d-%s", $document_id, $sentence_id, $section, $subsection, $node_original_id);

                    my $new_node = $new_tree->create_child();
                    $new_node->set_id($new_node_id);

                    $self->copy_atree($document_id, $sentence_id, $section, $subsection, $node, $new_node);
                }
            }
        }
        else {
            my $new_bundle = $document->create_bundle({'after' => $bundle, 'id' => sprintf("%s-%s", $bundle->id, $section)});
            my $new_tree = $new_bundle->create_tree("cs", "a", "cltt");
            foreach my $node (@section0_roots, @section_roots) {
                my $document_id = $self->_get_document_id($node);
                my $sentence_id = $self->_get_sentence_id($node);
                my $node_original_id = $self->_get_original_node_id($node);
                my $new_node_id = sprintf("a-document%s-sentence%d-multiplication%d.0-%s", $document_id, $sentence_id, $section, $node_original_id);

                my $new_node = $new_tree->create_child();
                $new_node->set_id($new_node_id);

                $self->copy_atree($document_id, $sentence_id, $section, 0, $node, $new_node);
            }
        }
    }
}

sub process_document {
    my ($self, $document) = @_;

    my @bundles = $document->get_bundles();
    foreach my $bundle (@bundles) {
        my $input_tree = $bundle->get_tree("cs", "a", "cltt");
        if ($self->_is_complex_sentence($input_tree)) {
            $self->multiplicate_complex_sentence($document, $bundle, $input_tree);
            $bundle->remove();
        }
    }
}

1;
