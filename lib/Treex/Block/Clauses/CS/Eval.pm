package Treex::Block::Clauses::CS::Eval;
use Moose;
use Treex::Core::Common;
extends 'Treex::Core::Block';

has 'clause_chart_threshold' => (
    is       => 'ro',
    isa      => 'Num',
    default  => 0
);

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

sub process_bundle {
    my ($self, $bundle) = @_;

    # Gold-standard.
    my $ref_zone = $bundle->get_zone($self->language, $self->selector);
    my @ref_parents = map { $_->get_parent->ord } $ref_zone->get_atree->get_descendants({ordered => 1});
    my $ref_label = $ref_zone->get_label;

    # Clause chart
    my $clause_chart = $self->get_clause_chart($ref_zone->get_atree);

    # Zoned to be evaluated and reported.
    my @compared_zones = grep { $_ ne $ref_zone && $_->language eq $self->language } $bundle->get_all_zones();
    $self->{compared_zones} = \@compared_zones;

    foreach my $compared_zone (@compared_zones) {
        my $label = $compared_zone->get_label;
        my @parents = map { $_->get_parent->ord } $compared_zone->get_atree->get_descendants({ordered => 1});

        if (@parents != @ref_parents) {
            log_fatal("There must be the same number of nodes in compared trees");
        }
        
        foreach my $i (0 .. $#parents) {
            my $eqp = $parents[$i] == $ref_parents[$i];

            $self->{stats}{total}{$label}{correct}++ if($eqp);
            $self->{stats}{$clause_chart}{$label}{correct}++ if($eqp);
        }

        $self->{stats}{total}{$label}{total} += @parents;
        $self->{stats}{$clause_chart}{$label}{total} += @parents;
    }

    $self->{n_sentences}{total}++;
    $self->{n_sentences}{$clause_chart}++;

    $self->{n_nodes}{total} += @ref_parents;
    $self->{n_nodes}{$clause_chart} += @ref_parents;
    
    return;
}

sub print_stats {
    my ($self) = @_;

    print "\n";
    print "**********\n";
    print "EVALUATION\n";
    print "**********\n";
    print "\n";

    # List of zone labels.
    my @compared_zones_labels = map { $_->get_label } @{$self->{compared_zones}};

    # Border.
    my $border = sprintf("%10s-+-%10s-+-%10s-+-%10s-+-%s\n", "----------", "----------", "----------", "----------", join("", map { sprintf("%11s-+-", "-----------") } @compared_zones_labels));

    # Header.
    printf("%10s | %10s | %10s | %10s | %s\n", "subset", "#sents", "#nodes", "weight", join("", map { sprintf("%11s | ", $_) } @compared_zones_labels));
    print $border;

    # Subset below threshold.
    $self->{n_sentences}{other} = 0;
    $self->{n_nodes}{other} = 0;
    foreach my $compared_zone_label (@compared_zones_labels) {
        $self->{stats}{other}{$compared_zone_label}{correct} = 0;
        $self->{stats}{other}{$compared_zone_label}{total} = 0;
    }

    # UAS for different subsets.
    foreach my $subset (reverse sort { $self->{n_nodes}{$a} <=> $self->{n_nodes}{$b} } keys %{$self->{stats}}) {
        my $weight = $self->{n_nodes}{$subset} / $self->{n_nodes}{total};

        # Clause chart agregation.
        if ($weight < $self->clause_chart_threshold) {
            $self->{n_sentences}{other} += $self->{n_sentences}{$subset};
            $self->{n_nodes}{other} += $self->{n_nodes}{$subset};
            foreach my $compared_zone_label (@compared_zones_labels) {
                $self->{stats}{other}{$compared_zone_label}{correct} += $self->{stats}{$subset}{$compared_zone_label}{correct};
                $self->{stats}{other}{$compared_zone_label}{total} += $self->{stats}{$subset}{$compared_zone_label}{total};
            }
            next;
        }

        if ($subset eq 'other') {
            next;
        }

        $self->print_one_line($subset);

        if ($subset eq 'total') {
            print $border;
        }
    }

    print $border;
    $self->print_one_line('other');
    print $border;

    print "\n";
}

sub print_one_line {
    my ($self, $subset) = @_;

    my @compared_zones_labels = map { $_->get_label } @{$self->{compared_zones}};
    
    printf("%10s | ", $subset);
    printf("%10d | ", $self->{n_sentences}{$subset});
    printf("%10d | ", $self->{n_nodes}{$subset});
    printf("    %.4f | ", $self->{n_nodes}{$subset} / $self->{n_nodes}{total});
    foreach my $compared_zone_label (@compared_zones_labels) {
        my $accuracy = 0;
        if ($self->{stats}{$subset}{$compared_zone_label}{total} > 0) {
            $accuracy = $self->{stats}{$subset}{$compared_zone_label}{correct} / $self->{stats}{$subset}{$compared_zone_label}{total};
        }

        printf("     %.4f | ", $accuracy);
    }
    printf("\n");
}

sub process_end {
    my ($self) = @_;

    $self->print_stats();
}

1;

=over

=item Treex::Block::Clauses::CS::Eval

Evaluation of the dependency parsing, especially for parsing meta-algorithm by Kriz and Hladka (2016).
It takes selected zone as a gold-standard and calculates statistics for all other zones against this gold-standard.
Using option different_clasues=1 it reports UAS for all different clause structures.

=back

=cut

=head1 COPYRIGHT AND LICENSE

Copyright © 2016 by Vincent Kriz <kriz@ufal.mff.cuni.cz>

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
