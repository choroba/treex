package Treex::Block::INTLIB::DBE;

## Vincent Kriz, 2014
## Nacte *.treex subor s morfosyntaktickou analyzov pojmov a inicializuje DBE

use Moose;
use Treex::Core::Common;
extends 'Treex::Core::Block';

has starting_entity_id => (
    is            => 'ro',
    isa           => 'Int',
    default       => 0,
);

has types_file => (
    is            => 'ro',
    isa           => 'Str',
    default       => '',
    documentation => 'CSV file with types and subtypes.',
);

has synonyms_file => (
    is            => 'ro',
    isa           => 'Str',
    default       => '',
    documentation => 'CSV file with synonyms.',
);

has output_file => (
    is            => 'ro',
    isa           => 'Str',
    default       => '',
    documentation => 'XML file with output DBE.',
);

sub process_document {
    my ($self, $document) = @_;
    my $entity_id = $self->starting_entity_id;

    ## Load synonyms
    my %synonyms = ();
    if (-f $self->synonyms_file()) {
        open(FILE, "<" . $self->synonyms_file());
        binmode(FILE, ":encoding(utf-8)");
        while (<FILE>) {
            chomp($_);
            my @fields = split(/;/, $_);
            my $pojem = shift(@fields);
    
            foreach my $entity (@fields) {
                if (!$entity) {
                    next;
                }
    
                $synonyms{$entity} = $pojem;
            }
        }
        close(FILE);
    }

    ## Load types definitions
    my %types = ();
    if (-f $self->types_file()) {
        open(FILE, "<" . $self->types_file());
        binmode(FILE, ":encoding(utf-8)");
        while (<FILE>) {
            chomp($_);
            my @fields = split(/;/, $_);
            my $pojem = shift(@fields);
    
            my $type = pop(@fields);
            while (!$type) {
                $type = pop(@fields);
            }
    
            $types{$pojem} = $type;
        }
        close(FILE);
    }

    ## Initialize DBE
    open(OUTPUT, ">" . $self->output_file());
    binmode(OUTPUT, ":encoding(utf-8)");
    print OUTPUT "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n";
    print OUTPUT "<entities>\n";

    ## Process each entity
    for my $bundle ($document->get_bundles) {
        for my $zone ($bundle->get_all_zones) {
            for my $tree ($zone->get_all_trees) {
                # Obtain entity tokens
                my @nodes = sort {$a->get_attr('ord') <=> $b->get_attr('ord')} $self->_serialize_sentence($tree);
                my @text = map {$_->get_attr('form')} @nodes;

                # Reconstruct original entity
                my $entity = "";
                foreach my $node (@nodes) {
                    $entity .= $node->get_attr('form');
                    $entity .= " " if ($node->get_attr('no_space_after') ne "1");
                }
                $entity =~ s/\s+$//;

                # Search for entity type
                if (!defined($types{$entity}) and defined($synonyms{$entity})) {
                    $types{$entity} = $types{$synonyms{$entity}};
                }
                if (!defined($types{$entity})) {
                    print STDERR "WARNING: Unknown entity type for '$entity'. Using default type.\n";
                }
                my $type = defined($types{$entity}) ? $types{$entity} : "Entity";

                # Write entity into DBE
                $entity_id++;
                print OUTPUT "\t<entity id=\"". sprintf('%04d', $entity_id) . "\">\n";
                print OUTPUT "\t\t<type>$type</type>\n";
                print OUTPUT "\t\t<original_form>$entity</original_form>\n";
                print OUTPUT "\t\t<lemmatized>" . join(" ", map {$_->get_attr('lemma')} @nodes) . "</lemmatized>\n";
                print OUTPUT "\t\t<dependency_tree>\n";
                foreach my $node (@nodes) {
                    print OUTPUT "\t\t\t<word form=\"" . $node->get_attr('form') . "\" lemma=\"" . $node->get_attr('lemma') . "\" tag=\"" . $node->get_attr('tag') . "\" ord=\"" . $node->get_attr('ord') . "\" parent=\"" . $node->get_parent()->get_attr('ord') . "\"/>\n";
                }
                print OUTPUT "\t\t</dependency_tree>\n";
                print OUTPUT "\t\t<pml_tq>" . $self->_get_pml_tree_query(0, @nodes) . "\n &gt;&gt; for " . join(", ", map {"\$n" . $_->ord . ".id"} @nodes) . " give  " . join(", ", map {"\$" . $_->ord} @nodes) . "</pml_tq>\n";
                print OUTPUT "\t</entity>\n";
            }
        }
    }

    print OUTPUT "</entities>\n";
    close(OUTPUT);
}

sub _get_pml_tree_query {
    my ($self, $current_nodes_parent, @nodes) = @_;
    log_info("PMLTQ : $current_nodes_parent");
    log_info("PMLTQ : @nodes");

    my @current_childs = ();
    foreach my $node (sort {$a->get_attr('ord') <=> $b->get_attr('ord')} @nodes) {
        log_info("      : " . $node->form  . " " . $node->parent->ord . " " . $node->ord);
        if ($node->parent->ord == $current_nodes_parent) {
            push(@current_childs, $node)
        }
    }
    log_info("PMLTQ : Current layer ($current_nodes_parent) nodes : @current_childs");

    my @subqueries = ();
    foreach  my $node (@current_childs) {
        my $node_id = $node->ord;
        my $current_node_query = "a-node \$n$node_id := [ m/lemma = \"". $node->lemma . "\"";
        my $children_queries = $self->_get_pml_tree_query($node->ord, @nodes);
        if ($children_queries) {
            $current_node_query .= " , $children_queries";
        }
        $current_node_query .= " ]";
        push(@subqueries, $current_node_query);
    }

    return join(", ", @subqueries);
}

sub _serialize_sentence {
    my ($self, $node) = @_;
    my @nodes = ();

    push(@nodes, $node) if ($node->get_attr('id') !~ /root/);

    foreach my $child ($node->get_children()) {
        push(@nodes, $self->_serialize_sentence($child));
    }

    return @nodes;
}

1;
