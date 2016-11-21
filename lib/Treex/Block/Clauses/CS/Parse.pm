package Treex::Block::Clauses::CS::Parse;
use Moose;
use Treex::Core::Common;
use Treex::Core::Config;

extends 'Treex::Block::W2A::CS::ParseMSTAdapted';

has 'verbose' => (
    is       => 'ro',
    isa      => 'Int',
    default  => 0
);

has 'parsing_mode' => (
    is       => 'ro',
    isa      => 'Str',
    default  => 'ccp'
);

# Verbose printing conditioned by $self->verbose.
# Printing uses treex logging system, namely log_info() method.
sub print_verbose {
    my ($self, $message) = @_;

    if ($self->verbose <= 0) {
        return;
    }

    log_info($message);
}

# Return a Clause Chart using annotation provided by Clause::CS::(Gold)ClauseChart.
sub get_clause_chart {
    my ($self, $a_root) = @_;

    my @a_nodes = $a_root->get_descendants({ordered => 1});
    my $cg = join("", (map {$_->{CG}} @a_nodes));
    $cg =~ s/0+/0/g;
    $cg =~ s/1+/1/g;
    $cg =~ s/2+/2/g;
    $cg =~ s/3+/3/g;
    $cg =~ s/4+/4/g;
    $cg =~ s/5+/5/g;
    $cg =~ s/6+/6/g;
    $cg =~ s/7+/7/g;
    $cg =~ s/8+/8/g;
    $cg =~ s/9+/9/g;
    $cg =~ s/B+/B/g;
    $cg =~ s/B$//g;

    return $cg;
}

# Return maximal clause_number as a number of clauses.
sub get_number_of_clauses {
    my ($self, $a_root) = @_;
    my $n_clauses = 0;

    my @a_nodes = $a_root->get_descendants({ordered => 1});
    foreach my $node (@a_nodes) {
        my $clause_number = defined($node->clause_number) ? $node->clause_number : 0;
        if ($clause_number > $n_clauses) {
            $n_clauses = $clause_number;
        }
    }

    return $n_clauses;
}

# Initialize a structure for parsing algorithm, aka clause tree as defined by Kriz and Hladka (2016).
# A structure represent one clause, it groups several nodes together and has a hierarchical structure.
# It could contain several substructures.
sub init_clause_structure {
    my ($self, $a_root) = @_;
    my @structure = ();

    my $current_block = undef;
    my $previous_tag = undef;
    my @a_nodes = $a_root->get_descendants({ordered => 1});
    foreach my $node (@a_nodes) {
        if (defined($current_block) and $previous_tag eq $node->{CG}) {
            push(@{$current_block->{nodes}}, $node);
            next;
        }

        if (defined($current_block) and $previous_tag ne $node->{CG}) {
            push(@structure, $current_block);
        }

        $current_block = {};
        $previous_tag = $node->{CG};
        if ($node->{CG} =~ /^\d+$/) {
            $current_block->{type} = "clause";
            $current_block->{nodes} = [$node];
            $current_block->{deep} = $node->{CG};
        }
        else {
            $current_block->{type} = "boundary";
            $current_block->{nodes} = [$node];
            $current_block->{deep} = "-";
        }
    }
    push(@structure, $current_block);

    return \@structure;
}

# Pretty print of the given clause structure to STDERR.
sub print_clause_structure {
    my ($self, $ra_clause_structure) = @_;

    $self->print_verbose("");
    $self->print_verbose("****************");
    $self->print_verbose("CLAUSE STRUCTURE");
    $self->print_verbose("****************");
    $self->print_verbose("");

    $self->print_verbose("Id | Type     | Deep | Head | Nodes");
    $self->print_verbose("---+----------+------+------+---------------------------------------------------------------------");
    for (my $i = 0; $i < scalar(@{$ra_clause_structure}); $i++) {
        my $has_head = 0;
        if (defined($$ra_clause_structure[$i]->{head})) {
            $has_head = 1;
        }

        my @colored_forms = ();
        foreach my $node (@{$$ra_clause_structure[$i]->{nodes}}) {
            my $node_id = $node->id;
            if ($has_head and scalar(grep(/^$node_id$/, (map {$_->id} @{$$ra_clause_structure[$i]->{head}})))) {
                push(@colored_forms, "\e[1;31m" . $node->form . "\e[m");
            }
            else {
                push(@colored_forms, $node->form);
            }
        }

        $self->print_verbose(sprintf("%2d | %8s | %4s | %4s | %s", $i, $$ra_clause_structure[$i]->{type}, $$ra_clause_structure[$i]->{deep}, $has_head, join(" ", @colored_forms)));
    }

    $self->print_verbose("");
}

# In the given dependency tree defined by (1) a list of nodes, (2) a list of nodes' parents and (3) a list of a-funs
# identify the clause head nodes as used in the Clause Chart Parsing meta-algorithm.
# A clause head is usually a root node and some other stuff (e.g. AuxT, AuxV children)
sub get_clause_head {
    my ($self, $ra_nodes, $ra_parents, $ra_afuns) = @_;
    my @head = ();

    # Identify root of the given tree.
    my $root_node_identification = 0;
    my $root_node = undef;

    # Skip root-node if it is a head of the coordination.
    FIND_HEAD:
    for (my $i = 0; $i < scalar(@$ra_parents); $i++) {
        if ($$ra_parents[$i] == $root_node_identification) {
            if ($$ra_afuns[$i] =~ /Coord/) {
                $root_node_identification = $i + 1;
                goto FIND_HEAD;
            }
            else {
                $root_node = $i + 1;
                last;
            }
        }
    }

    # Head is the node with the parent = 0 and some other stuff defined later.
    for (my $i = 0; $i < scalar(@$ra_parents); $i++) {
        my $parent = $$ra_parents[$i];

        if (scalar(@head) == 0 and $parent == $root_node_identification and $$ra_nodes[$i]->tag !~ /^Z/) {
            push(@head, $$ra_nodes[$i]);

            for (my $j = 0; $j < scalar(@$ra_parents); $j++) {
                my $parent = $$ra_parents[$j];
                if ($parent == $i + 1 and $$ra_afuns[$j] =~ /^(AuxT|AuxV)$/) {
                    if ($j < $i) {
                        @head = ($$ra_nodes[$j], @head);
                    }
                    else {
                        @head = (@head, $$ra_nodes[$j]);
                    }
                }
            }
        }
    }

    # Pretty print with the head annotation.
    # print STDERR "\n";
    # print STDERR "Ord | Id                             | Form         | Tag             |    Afun | Parent | Head\n";
    # print STDERR "----+--------------------------------+--------------+-----------------+---------+--------+-----\n";
    # for (my $i = 0; $i < scalar(@$ra_parents); $i++) {
    #     my $node = $$ra_nodes[$i];
    #     my $node_ord = $node->ord();
    #     my $head_node = scalar(grep(/^$node_ord$/, map {$_->ord()} @head)) ? "1" : "0";

    #     # Debug.
    #     print STDERR sprintf("%3d | %30s | %12s | %15s | %7s | %6d | %d\n", $i + 1, $$ra_nodes[$i]->id, $$ra_nodes[$i]->form,
    #         $$ra_nodes[$i]->tag, $$ra_afuns[$i], $$ra_parents[$i], $head_node);
    # }

    return \@head;
}

# This method return a list of clause structured which should be parsed in the current state of the algorithm.
# Actually, 3 possibilities are common:
# (1) there are 2+ neighbored coordinated clauses on the deepest layer -> return the longest sequence of such clauses as a next algorithm sub-task to parse
# (2) there are 2+ neighbored subordinated clauses -> return the longest sequence of such clauses
# (3) otherwise return undef
sub get_next_subtask {
    my ($self, $c_structure) = @_;

    # Find deepest block.
    my $deepest_block = 0;
    foreach my $block (@$c_structure) {
        if ($block->{type} eq "tree" and $deepest_block < $block->{deep}) {
            $deepest_block = $block->{deep};
        }
    }

    # Initialize.
    my @candidates = undef;
    my @sorted_candidates = undef;

    # Find all coordinated sequences.
    @candidates = ();
    for (my $i = 0; $i < scalar(@$c_structure); $i++) {
        if ($$c_structure[$i]->{type} eq 'boundary') {
            next;
        }

        if ($$c_structure[$i]->{deep} != $deepest_block) {
            next;
        }

        my @sequence = ($i);
        for (my $j = $i + 1; $j < scalar(@$c_structure); $j++) {
            if ($$c_structure[$j]->{type} eq 'boundary') {
                push(@sequence, $j);
                next;
            }

            if ($$c_structure[$j]->{deep} == $deepest_block) {
                push(@sequence, $j);
            }
            else {
                last;
            }
        }

        if ($$c_structure[$sequence[$#sequence]]->{type} eq 'boundary') {
            pop(@sequence);
        }

        if (scalar(@sequence) >= 3) {
            push(@candidates, \@sequence);
        }
    }

    # Find maximal sequence.
    @sorted_candidates = reverse sort {scalar(@$a) <=> scalar(@$b)} @candidates;
    if (scalar(@sorted_candidates)) {
        return {type => 'coord', blocks => $sorted_candidates[0]}
    }

    # Find maximal subordinated sequence.
    @candidates = ();
    for (my $i = 0; $i < scalar(@$c_structure); $i++) {
        if ($$c_structure[$i]->{type} eq 'boundary') {
            next;
        }

        my @sequence = ($i);
        for (my $j = $i + 1; $j < scalar(@$c_structure); $j++) {
            if ($$c_structure[$j]->{type} eq 'boundary') {
                push(@sequence, $j);
                next;
            }

            if ($$c_structure[$j]->{deep} == $$c_structure[$sequence[$#sequence] - 1]->{deep} + 1) {
                push(@sequence, $j);
            }
            else {
                last;
            }
        }

        if ($$c_structure[$sequence[$#sequence]]->{type} eq 'boundary') {
            pop(@sequence);
        }

        if (scalar(@sequence) >= 3) {
            push(@candidates, \@sequence);
        }
    }

    # Find maximal sequence.
    @sorted_candidates = reverse sort {scalar(@$a) <=> scalar(@$b)} @candidates;
    if (scalar(@sorted_candidates)) {
        return {type => 'subord', blocks => $sorted_candidates[0]}
    }

    return undef;
}

# Return 1 if given boundary block contain subordinate conjunction.
sub is_subordinate_boundary {
    my ($self, $block) = @_;

    foreach my $node (@{$block->{nodes}}) {
        if ($node->tag =~ /^J,/) {
            return 1;
        }
    }

    return 0;
}

# Obtain data from parsing sub-tasks from given clause structure
# and build the final dependency tree. Return a hash with following structure:
# {node_id}{parent}, {node_id}{afun}.
sub build_final_tree {
    my ($self, $ra_c_structure) = @_;

    # Convert array-ref to array.
    my @c_structure = @$ra_c_structure;

    my %data = ();
    foreach my $block (@c_structure) {
        # Obtain data from trees recursively.
        if ($block->{type} eq "tree") {
            for (my $i = 0; $i < scalar(@{$block->{nodes}}); $i++) {
                $data{${$block->{nodes}}[$i]->id}{parent} = $block->{local2global}{${$block->{parents}}[$i]};
                $data{${$block->{nodes}}[$i]->id}{afun} = ${$block->{afuns}}[$i];
            }

            if (!defined($block->{children})) {
                next;
            }

            my %children_data = $self->build_final_tree($block->{children});
            foreach my $node_id (keys %children_data) {
                if (defined($data{$node_id})) {
                    next;
                }

                $data{$node_id}{parent} = $children_data{$node_id}{parent};
                $data{$node_id}{afun} = $children_data{$node_id}{afun};
            }
        }

        # Append boundary to root with AuxK afun.
        if ($block->{type} eq "boundary") {
            foreach my $node (@{$block->{nodes}}) {
                $data{$node->id}{parent} = 0;
                $data{$node->id}{afun} = 'AuxK';
            }
        }
    }

    # Define parent to 0 for nodes which have still undefined parent.
    foreach my $node_id (keys %data) {
        if (!defined($data{$node_id}{parent})) {
            $data{$node_id}{parent} = 0;
        }
    }

    return %data;
}

# For debug, parse whole sentence in a standard way.
# Return the same data structure as build_final_tree().
sub full_scale_parsing {
    my ($self, $a_root) = @_;

    my @a_nodes = $a_root->get_descendants({ordered => 1});
    my @words = map { $_->form } @a_nodes;
    my @tags = map { $_->tag } @a_nodes;

    my ($parents_rf, $afuns_rf) = $self->_parser->parse_sentence(\@words, undef, \@tags);

    my %data = ();
    foreach my $i ( 0 .. $#a_nodes) {
        my $node_id = $a_nodes[$i]->id;
        $data{$node_id}{parent} = $$parents_rf[$i];
        $data{$node_id}{afun} = $$afuns_rf[$i];
    }

    return %data;
}

sub get_parsing_data {
    my ($self, $a_root) = @_;

    # Extract parsed data.
    my @a_nodes = $a_root->get_descendants({ordered => 1});

    my %data = ();
    foreach my $a_node (@a_nodes) {
        my $node_id = $a_node->id;
        $data{$node_id}{parent} = $a_node->get_parent->ord;
        $data{$node_id}{afun} = $a_node->get_parent->afun;
    }

    return %data;
}

sub chunk_parsing {
    my ($self, $a_root) = @_;

    # Call process_atree() from BaseChunkParser.
    $self->SUPER::process_atree($a_root);

    # Return the topology.
    return $self->get_parsing_data($a_root);
}

sub merge_clause_structure {
    my ($self, $c_structure) = @_;
    my $merge = {
        'type' => 'clause',
        'deep' => 0,
        'nodes' => [],
        'children' => [@$c_structure]
    };

    foreach my $block (@$c_structure) {
        if ($block->{type} eq 'boundary') {
            push(@{$merge->{nodes}}, (@{$block->{nodes}}));
        }
        elsif ($block->{type} eq 'tree') {
            push(@{$merge->{nodes}}, (@{$block->{nodes}}));
        }
        elsif ($block->{type} eq 'clause') {
            push(@{$merge->{nodes}}, (@{$block->{nodes}}));
        }
    }

    return [$merge];
}

sub ccp_parsing {
    my ($self, $a_root) = @_;

    # Initialize a clause structure.
    my $c_structure = $self->init_clause_structure($a_root);
    $self->print_clause_structure($c_structure);
    $self->print_verbose("");

    # Obtain a clause chart.
    $self->print_verbose("************");
    $self->print_verbose("CLAUSE CHART");
    $self->print_verbose("************");
    $self->print_verbose("");
    my $cg = $self->get_clause_chart($a_root);
    $self->print_verbose($cg);
    $self->print_verbose("");

    # For simple sentences (clause chart = '0') use chunk
    # parser method...
    if ($cg =~ /^(0|0B1)B?$/) {
        $self->chunk_parsing($a_root);
        return $self->get_parsing_data($a_root);
    }

    # Process the structure while there are more than 2 blocks.
    my $changed_c_structure = 1;
    while ($changed_c_structure) {
        # To prevert empty cycles, use $changed_c_structure to inform that C-structure was changed.
        $changed_c_structure = 0;

        # Debug.
        $self->print_clause_structure($c_structure);

        # When there is only one clause in the sentence, use standard parser.
        # To provide standard parsing, merge all c-structure blocks back into one block.
        my $n_clauses = $self->get_number_of_clauses($a_root);
        if ($n_clauses == 1) {
            $c_structure = $self->merge_clause_structure($c_structure);
            $self->print_clause_structure($c_structure);
        }

        # Parse each clause independently. Identify the head of each clause.
        $self->print_verbose("***************");
        $self->print_verbose("PARSING CLAUSES");
        $self->print_verbose("***************");
        $self->print_verbose("");
        for (my $i = 0; $i < scalar(@{$c_structure}); $i++) {
            if ($$c_structure[$i]->{type} ne "clause") {
                $self->print_verbose(sprintf("Processing c-structure block %2d : skip non-clause block", $i));
                next;
            }

            # Obtain list of tokens and tags.
            my @words = map { $_->form } @{$$c_structure[$i]->{nodes}};
            my @tags  = map { $_->tag } @{$$c_structure[$i]->{nodes}};

            # Prepare mapping between local ord and global ord.
            my $local2global = {};
            my @ords  = map { $_->ord } @{$$c_structure[$i]->{nodes}};
            for (my $j = 1; $j <= scalar(@ords); $j++) {
                $local2global->{$j} = $ords[$j - 1];
            }

            # Debug.
            $self->print_verbose(sprintf("Processing c-structure block %2d : (%s)", $i, join(" ", @words)));

            # Call parser.
            my ($parents_rf, $afuns_rf) = $self->_parser->parse_sentence(\@words, undef, \@tags);

            # Obtain head of the clause.
            my $head_nodes = $self->get_clause_head($$c_structure[$i]->{nodes}, $parents_rf, $afuns_rf);

            # Save data into C-structure.
            $$c_structure[$i]->{type} = "tree";
            $$c_structure[$i]->{head} = $head_nodes;
            $$c_structure[$i]->{parents} = $parents_rf;
            $$c_structure[$i]->{afuns} = $afuns_rf;
            $$c_structure[$i]->{local2global} = $local2global;

            # Propagate that C-structure was changed.
            $changed_c_structure = 1;
        }

        # Debug current state of the clause structure.
        $self->print_clause_structure($c_structure);

        # FIXME
        $self->print_verbose("*******");
        $self->print_verbose("SUBTASK");
        $self->print_verbose("*******");
        $self->print_verbose("");
        my $what_to_merge = $self->get_next_subtask($c_structure);
        if (defined($what_to_merge)) {
            # Debug.
            $self->print_verbose("Merge type : $what_to_merge->{type}");
            $self->print_verbose("C-blocks   : @{$what_to_merge->{blocks}}");

            my $block = undef;

            if ($what_to_merge->{type} eq 'coord') {
                my @blocks = @{$what_to_merge->{blocks}};

                my @nodes = ();
                my @children = ();
                foreach my $block_id (@blocks) {
                    if ($$c_structure[$block_id]->{type} eq 'boundary') {
                        push(@nodes, @{$$c_structure[$block_id]->{nodes}});
                    }
                    else {
                        push(@nodes, @{$$c_structure[$block_id]->{head}});
                    }
                    push(@children, $$c_structure[$block_id])
                }

                $block = {
                    'type' => 'clause',
                    'deep' => $$c_structure[$blocks[0]]->{deep},
                    'nodes' => \@nodes,
                    'children' => \@children
                };
            }

            if ($what_to_merge->{type} eq 'subord') {
                my @blocks = @{$what_to_merge->{blocks}};

                my @nodes = ();
                my @children = ();
                foreach my $block_id (@blocks) {
                    if ($$c_structure[$block_id]->{type} eq 'boundary') {
                        push(@nodes, @{$$c_structure[$block_id]->{nodes}});
                    }
                    else {
                        push(@nodes, @{$$c_structure[$block_id]->{nodes}});
                    }
                    push(@children, $$c_structure[$block_id])
                }

                $block = {
                    'type' => 'clause',
                    'deep' => $$c_structure[$blocks[0]]->{deep},
                    'nodes' => \@nodes,
                    'children' => \@children
                };
            }

            # Store info about merging into node with ord 1.
            my @a_nodes = $a_root->get_descendants({ordered => 1});
            $a_nodes[0]->{wild}{merge} = $what_to_merge->{type};
            $a_nodes[0]->serialize_wild();

            # Slice three merged blocks from c_structure and add the new one.
            splice(@$c_structure, ${$what_to_merge->{blocks}}[0], scalar(@{$what_to_merge->{blocks}}), $block)
        }
        else {
            $self->print_verbose("No subtask.");
        }

        # Terminate when c-structure = (tree, boundary).
        if (scalar(@$c_structure) == 2 and
            $$c_structure[0]->{type} eq "tree" and $$c_structure[1]->{type} eq "boundary") {
            $self->print_verbose("Ending parsing with c-structure (tree, boundary).");
            last;
        }

        # Terminate when c-structure = (tree).
        if (scalar(@$c_structure) == 1 and $$c_structure[0]->{type} eq "tree") {
            $self->print_verbose("Ending parsing with c-structure (tree).");
            last;
        }

        # Fall-back: When there is still no change in the structure,
        # parse the rest of the sentence with the standard parser.
        if (!$changed_c_structure) {
            $self->print_verbose("No changes in c-structure. Using fall-back.");
            $c_structure = $self->merge_clause_structure($c_structure);
            $changed_c_structure = 1;
        }

        $self->print_verbose("");
    }

    # Build final tree.
    $self->print_verbose("");
    $self->print_verbose("**********************");
    $self->print_verbose("BUILDING ORIGINAL TREE");
    $self->print_verbose("**********************");
    $self->print_verbose("");
    return $self->build_final_tree($c_structure);
}

sub process_atree {
    my ($self, $a_root) = @_;

    # Print parsing task ID.
    $self->print_verbose("");
    $self->print_verbose("================================================================================================");
    $self->print_verbose("CLAUSAL PARSING : \e[1;32m" . $a_root->id . "\e[m");
    $self->print_verbose("================================================================================================");
    $self->print_verbose("");

    # Print input sentence.
    $self->print_verbose("**************");
    $self->print_verbose("INPUT SENTENCE");
    $self->print_verbose("**************");
    $self->print_verbose("");
    $self->print_verbose("\e[1;33m" . join(" ", map {$_->form} $a_root->get_descendants({ordered => 1})) . "\e[m");
    $self->print_verbose("");

    # The whole CCP meta-algorithm provide just when parsing mode is set to 'ccp'.
    my %ccp = ();
    if ($self->parsing_mode eq 'ccp') {
        %ccp = $self->ccp_parsing($a_root);
    }

    # Baseline parsing obtain on both modes.
    my %mst = $self->full_scale_parsing($a_root);

    # Accoring to parsing mode, fill final dependences from cpp or mst.
    my %final = ();
    if ($self->parsing_mode eq 'baseline') {
        %final = %mst;
    }
    else {
        %final = %ccp;
    }

    # Debug.
    $self->print_verbose("Id                             | Form             | Afun    | Ord | CPP Parent | MST Parent | Diff");
    $self->print_verbose("-------------------------------+------------------+---------+-----+------------+------------+-----");
    my @a_nodes = $a_root->get_descendants({ordered => 1});
    foreach my $node (@a_nodes) {
        my $node_id = $node->id;
        my $diff = $final{$node_id}{parent} eq $mst{$node_id}{parent} ? "" : "X";

        $self->print_verbose(sprintf("%30s | %16s | %7s | %3d | %10d | %10d | %4s", $node_id, $node->form, $final{$node_id}{afun}, $node->ord, $final{$node_id}{parent}, $mst{$node_id}{parent}, $diff));
        #printf("%30s | %16s | %7s | %3d | %10d | %10d | %4s\n", $node_id, $node->form, $final{$node_id}{afun}, $node->ord, $final{$node_id}{parent}, $mst{$node_id}{parent}, $diff);
    }
    $self->print_verbose("");

    # Final setting of parent and afun as the output of the Parsing.
    # Delete old topology.
    foreach my $a_node (@a_nodes) {
        $a_node->set_parent($a_root);
    }

    unshift @a_nodes, $a_root;

    for (my $i = 1; $i < scalar(@a_nodes); $i++) {
        my $node_id = $a_nodes[$i]->id;

        if ($final{$node_id}{afun} =~ s/_.+//) {
            $a_nodes[$i]->set_is_member(1);
        }
        $a_nodes[$i]->set_parent($a_nodes[$final{$node_id}{parent}]);
        $a_nodes[$i]->set_afun($final{$node_id}{afun});
    }
}

1;

__END__

=over

=item Treex::Block::Clauses::CS::Parse

Meta algorithm for parsing using Clausal Graphs by Vincent Kriz.
The parsing task on the whole sentence is split into several independent sub-tasks.
Individual parsing sub-tasks are solved by McDonald's MST parser adapted by Zdenek Zabokrtsky and Vaclav Novak.

=back

=cut

=head1 COPYRIGHT AND LICENSE

Copyright © 2016 by Vincent Kriz <kriz@ufal.mff.cuni.cz>

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
