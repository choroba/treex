package Treex::Block::Clauses::CS::Analyze0B1;

use Moose;
use Treex::Core::Common;
use Treex::Core::Node;
use Treex::Block::Clauses::CS::Parse;

extends 'Treex::Block::W2A::CS::ParseMSTAdapted';

has 'clause_chart_threshold' => (
    is       => 'ro',
    isa      => 'Num',
    default  => 0
);

# Direct calling of the MST Parser.
sub parse {
    my ($self, $ra_words, $ra_tags) = @_;

    my @words = @$ra_words;
    my @tags = @$ra_tags;

    foreach my $i (0 .. $#tags) {
        my @positions = split //, $tags[$i];
        $tags[$i] = $positions[4] eq '-' ? "$positions[0]$positions[1]" : "$positions[0]$positions[4]";
    }

    return $self->_parser->parse_sentence(\@words, undef, \@tags);
}

sub get_simple_subordinated_clause {
    my ($self, $boundary) = @_;

    my $lexicalized_boundary = join('_', map {$_->lemma} @{$boundary->{nodes}});
    if ($lexicalized_boundary eq ",_který") {
        my $ktery_node = ${$boundary->{nodes}}[1];
        if ($ktery_node->tag =~ /^...P/) {
            return ["jsou", "VB-P---3P-AA---"];
        }
        else {
            return ["je", "VB-S---3P-AA---"];
        }
    }

    return undef;
}

sub detect_head {
    my ($self, $main_clause, $boundary, $subordinated_clause) = @_;

    print "\n\n\n--------\n";
    print "0 clause : " . join(" ", map {$_->form} @{$main_clause->{nodes}}) . "\n";
    print "boundary : " . join(" ", map {$_->form} @{$boundary->{nodes}}) . "\n";
    print "1 clause : " . join(" ", map {$_->form} @{$subordinated_clause->{nodes}}) . "\n\n";

    # Define the sample verb as a simplification of the 1-clause.
    my $verb_data = $self->get_simple_subordinated_clause($boundary);
    if (!defined($verb_data)) {
        print "--> NO VERB\n\n\n";
        return undef;
    }
    print "1 verb   : " . join("/", @$verb_data) . "\n";

    # Parse main clause, boundary and the subordinated verb.
    my @nodes = (@{$main_clause->{nodes}}, @{$boundary->{nodes}});
    my @words = ((map { $_->form } @nodes), $$verb_data[0]);
    my @tags = ((map { $_->tag } @nodes), $$verb_data[1]);
    print "parsing  : " . join(" ", @words) . "\n";
    my ($parents_rf, $afuns_rf) = $self->parse(\@words, \@tags);
    print "\n";

    # Find the parent of the 1-verb.
    my $detected_parent = $nodes[$$parents_rf[-1] - 1];
    print "parent ord : " . $$parents_rf[-1] . "\n";
    print "detected   : " . $detected_parent->form . "\n";

    return $detected_parent;
}

sub process_bundle {
    my ($self, $bundle) = @_;

    # Gold-standard.
    my $ref_zone = $bundle->get_zone($self->language, $self->selector);
    my %nodes = ();
    my $a_root = $ref_zone->get_atree;
    foreach my $node ($ref_zone->get_atree->get_descendants({ordered => 1})) {
        $nodes{$node->id} = "";
    }

    # Clause chart
    my $clause_chart = Treex::Block::Clauses::CS::Parse::get_clause_chart(undef, $ref_zone->get_atree);
    if ($clause_chart ne '0B1') {
        return;
    }

    # Extract lexicalized boundary.
    my $clause_structure = Treex::Block::Clauses::CS::Parse::init_clause_structure(undef, $ref_zone->get_atree);
    my @boundary_nodes = ();
    my $ktery_node = undef;
    my $subordinated_clause_root = undef;
    my $lexicalized_boundary = '';
    foreach my $block (@$clause_structure) {
        if ($block->{type} eq 'boundary') {
            $lexicalized_boundary = join('_', map {$_->lemma} @{$block->{nodes}});
            last;
        }
    }
    foreach my $block (@$clause_structure) {
        if ($block->{type} eq 'boundary') {
            foreach my $node (@{$block->{nodes}}) {
                $nodes{$node->id} = 'boundary';
                if ($node->lemma eq 'který') {
                    $ktery_node = $node;
                }
            }
        }
        elsif ($block->{deep} =~ /^\d+$/ and $block->{deep} == 1) {
            my @clause_nodes = map { $_->ord } @{$block->{nodes}};
            foreach my $node (@{$block->{nodes}}) {
                my $node_parent = $node->parent->ord;
                if (scalar(grep(/^$node_parent$/, @clause_nodes)) == 0) {
                    # $nodes{$node->id} = 'root';
                    $nodes{$node->parent->id} = 'root';
                    $subordinated_clause_root = $node->parent;
                }
            }
        }
    }

    if ($lexicalized_boundary ne ",_který") {
        return;
    }

    print "\n\n\n";
    print "\n----------------------------------------------------------\n\n\n\n";
    printf("[ %s ] [ %s ]", $a_root->id, $lexicalized_boundary);
    print "\n\n";


    my $tag1 = $subordinated_clause_root->tag;
    my $tag2 = $ktery_node->tag;
    $self->{stats}{pos}{substr($tag1, 1, 1)} += 1;
    $self->{stats}{gender}{sprintf("%s -> %s", substr($tag1, 2, 1), substr($tag2, 2, 1))} += 1;
    $self->{stats}{number}{sprintf("%s -> %s", substr($tag1, 3, 1), substr($tag2, 3, 1))} += 1;
    print "\n";

    # Let's detect the 0-parent by the MST!
    my $identified_root = $self->detect_head($$clause_structure[0], $$clause_structure[1], $$clause_structure[2]);
    if ($identified_root) {
        $nodes{$identified_root->id} = 'detected';
    }

    print "\n\n";

    # Print whole sentence.
    # Highlight the root for C2 and the boundary.
    foreach my $node ($ref_zone->get_atree->get_descendants({ordered => 1})) {
        print "\t";

        if ($nodes{$node->id} eq 'root') {
            print "\e[1;31m"
        }
        elsif ($nodes{$node->id} eq 'detected') {
            print "\e[1;38m"
        }
        elsif ($nodes{$node->id} eq 'boundary') {
            print "\e[1;34m"
        }

        printf("%2d | %20s | %s | %5s | %2d", $node->ord, $node->form, $node->tag, $node->afun, $node->parent->ord);
        print "\e[m";
        print "\n";
    }

    print "\n";

    $self->{stats}{sentences} += 1;
    if ($identified_root == $subordinated_clause_root) {
        print "\tCorrect\n";
        $self->{stats}{correct} += 1;
    }

    print "\n";
    print "\n";
}

sub process_end {
    my ($self) = @_;

    $accuracy = $self->{stats}{correct} / $self->{stats}{sentences} * 100;
    print "total   : $self->{stats}{sentences}\n";
    print "correct : $self->{stats}{correct} ($accuracy)\n";
}

1;
