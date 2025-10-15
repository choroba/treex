#!/usr/bin/perl
use warnings;
use strict;
use utf8;

use Treex::Tool::UMR::PDTV2PB::Parser;

use Scalar::Util qw{ blessed };
use Treex::Core::BundleZone;

use Test::MockObject;
use Test2::V0;
plan(11);

my $p = 'Treex::Tool::UMR::PDTV2PB::Parser'->new;
ok $p, 'Instantiates';
like ${ $p->dsl }, qr/ Rule \s+ ::= /x, 'Has a DSL';
ok $p->grammar, 'Has a grammar';

my $delete = $p->parse('!delete');
ok blessed($delete), 'Blessed object';
ok blessed($delete)
    && $delete->isa('Treex::Tool::UMR::PDTV2PB::Transformation::Delete'),
    'Parses delete';

{   my $template = $p->parse('mít-CPHR-057');
    is $template->{template}->run(undef, undef, undef), 'mít-CPHR-057',
        'Parses a template';
}

{   my $error = $p->parse('!error');
    my $u = 'Test::MockObject'->new;
    $u->mock(id => sub { 'u00' });
    my $t = 'Test::MockObject'->new;
    $t->mock(id => sub { 't00' });
    like dies { $error->run($u, $t, undef) },
        qr{Valency transformation error: u00/t00}, 'Error';
}

{   my $setter = $p->parse('!modal-strength(neutral-negative)');
    my $u = 'Test::MockObject'->new;
    $u->mock(set_modal_strength => sub { $_[0]{modal_strength} = $_[1] });
    $setter->run($u, undef, undef);
    is $u,
        hash { field(modal_strength => 'neutral-negative'); end() },
        'Setter';
}

{   my $setter = $p->parse(
        '!modal-strength(echild.functor:PAT,neutral-negative)');
    my $t = 'Test::MockObject'->new;
    my $tch = 'Test::MockObject'->new;
    my $u = 'Test::MockObject'->new;
    my $uch = 'Test::MockObject'->new;
    my $modality;
    $t->mock(get_echildren => sub { $tch });
    $tch->mock(functor => sub { 'PAT' });
    $tch->mock(get_referencing_nodes => sub { $uch });
    $uch->mock(set_modal_strength => sub { $modality = $_[1] });
    $setter->run($u, $t, undef);
    is $modality, 'neutral-negative', 'node setter';
}

{   my $cond = $p->parse('if(functor:PAT)(ARG1)else(ARG2)');
    my $t = 'Test::MockObject'->new;
    $t->mock(functor => sub { 'PAT' });
    my $value = $cond->run(undef, $t, undef);
    is $value, 'ARG1', 'Condition Then';

    $t->mock(functor => sub { 'ADDR' });
    my $value = $cond->run(undef, $t, undef);
    is $value, 'ARG2', 'Condition Else';
}
