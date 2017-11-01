package Treex::Block::Coref::EN::PersPron::Resolve;
use Moose;
use Moose::Util::TypeConstraints;
use Treex::Core::Common;
extends 'Treex::Block::Coref::Resolve';
with 'Treex::Block::Coref::EN::PersPron::Base';

use Treex::Tool::ML::VowpalWabbit::Ranker;

has '+model_type' => ( isa => enum([qw/pcedt_bi pcedt_bi.with_en pcedt_bi.with_en.treex_cr pcedt_bi.with_en.base_cr/]), default => 'pcedt_bi' );

override '_build_model_for_type' => sub {
    my $dir = '/home/mnovak/projects/czeng_coref/treex_cr_train/en/perspron/tmp/ml';
    return {
        #'pcedt_bi' => "$dir/002_run_2017-01-16_10-52-26_15941.PCEDT.feats-AllMonolingual.round1/001.9fd0f3842c.featset/004.39acd.mlmethod/model/train.pcedt_bi.with_cs.table.gz.vw.ranking.model",
        'pcedt_bi' => "$dir/004_run_2017-01-17_22-34-27_28405.PCEDT.monolingual.feats-AllMonolingual/001.9fd0f3842c.featset/024.9c797.mlmethod/model/train.pcedt_bi.table.gz.vw.ranking.model",
        
        # PCEDT.crosslingual aligned_all
        'pcedt_bi.with_en' => "$dir/006_run_2017-01-19_00-20-54_11002.PCEDT.crosslingual.feats-AllMonolingual/002.28b9b793e5.featset/022.88cd4.mlmethod/model/train.pcedt_bi.with_cs.table.gz.vw.ranking.model",
        # PCEDT.crosslingual aligned_all+coref+mono_all
        'pcedt_bi.with_en.treex_cr' => "$dir/006_run_2017-01-19_00-20-54_11002.PCEDT.crosslingual.feats-AllMonolingual/004.191e9db554.featset/024.9c797.mlmethod/model/train.pcedt_bi.with_cs.table.gz.vw.ranking.model",
        
        # PCEDT.crosslingual-baseline aligned_all+coref+mono_all
        'pcedt_bi.with_en.base_cr' => "$dir/005_run_2017-01-18_15-41-57_22583.PCEDT.crosslingual-baseline.feats-AllMonolingual/004.191e9db554.featset/024.9c797.mlmethod/model/train.pcedt_bi.with_cs.baseline.table.gz.vw.ranking.model",
    };
};
override '_build_ranker' => sub {
    my ($self) = @_;
    my $ranker = Treex::Tool::ML::VowpalWabbit::Ranker->new( 
        { model_path => $self->model_path } 
    );
    return $ranker;
};

1;

#TODO adjust documentation

__END__

=encoding utf-8

=head1 NAME 

Treex::Block::Coref::EN::PersPron::Resolve

=head1 DESCRIPTION

Pronoun coreference resolver for English.
Settings:
* English personal pronoun filtering of anaphor
* candidates for the antecedent are nouns from current (prior to anaphor) and previous sentence
* English pronoun coreference feature extractor
* using a model trained by a perceptron ranker

=head1 AUTHORS

Michal Novák <mnovak@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2011-2016 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
