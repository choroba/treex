#!/usr/bin/perl
use warnings;
use strict;
use utf8;

use Treex::Tool::UMR::PDTV2PB::Parser;

use Scalar::Util qw{ blessed };
use Treex::Core::BundleZone;

use Test::MockObject;
use Test2::V0;
plan(23);

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

{   my $setter = $p->parse('!polarity(-)');
    my $u = 'Test::MockObject'->new;
    $u->mock(set_polarity => sub { $_[0]{polarity} = $_[1] });
    $setter->run($u, undef, undef);
    is $u,
        hash { field(polarity => '-'); end() },
        'Setter';
}

{   my $setter = $p->parse('!functor(ARG1)');
    my $u = 'Test::MockObject'->new;
    $u->mock(set_functor => sub { $_[0]{functor} = $_[1] });
    $setter->run($u, undef, undef);
    is $u,
        hash { field(functor => 'ARG1'); end() },
        'Setter';
}

{   my $setter = $p->parse('!t_lemma(mít-042)');
    my $u = 'Test::MockObject'->new;
    $u->mock(set_concept => sub { $_[0]{concept} = $_[1] });
    $setter->run($u, undef, undef);
    is $u,
        hash { field(concept => 'mít-042'); end() },
        'Setter';
}

{   my $setter = $p->parse('!aspect(habitual)');
    my $u = 'Test::MockObject'->new;
    $u->mock(set_aspect => sub { $_[0]{aspect} = $_[1] });
    $setter->run($u, undef, undef);
    is $u,
        hash { field(aspect => 'habitual'); end() },
        'Setter';
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
    my $value2 = $cond->run(undef, $t, undef);
    is $value2, 'ARG2', 'Condition Else';
}

{   my $cond = $p->parse('if(no-echild.functor:PAT)(ARG1)else(ARG2)');
    my $t = 'Test::MockObject'->new;
    my $tch = 'Test::MockObject'->new;
    $t->mock(get_echildren => sub { $tch });
    $tch->mock(functor => sub { 'PAT' });
    my $value = $cond->run(undef, $t, undef);
    is $value, 'ARG2', 'no-echild false';

    $tch->mock(functor => sub { 'ACT' });
    my $value2 = $cond->run(undef, $t, undef);
    is $value2, 'ARG1', 'no-echild true';

}

{   my $cond = $p->parse('if(esibling.functor:PAT)(ARG1)else(ARG2)');
    my $t = 'Test::MockObject'->new;
    my $tp = 'Test::MockObject'->new;
    my $ts = 'Test::MockObject'->new;
    $t->mock(get_eparents => sub { $tp });
    $t->mock(functor => sub { 'PAT' });
    $tp->mock(get_echildren => sub { $t, $ts });
    $ts->mock(functor => sub { 'PAT' });
    my $value = $cond->run(undef, $t, undef);
    is $value, 'ARG1', 'esibling true';

    $ts->mock(functor => sub { 'ACT' });
    my $value2 = $cond->run(undef, $t, undef);
    is $value2, 'ARG2', 'esibling false';
}

{   my $move = $p->parse('!move(esibling:PAT,possessor)');
    my ($u, $us, $tp, $t, $ts1, $ts2)
        = map 'Test::MockObject'->new, 1 .. 6;
    $t->mock(get_eparents => sub { $tp });
    $tp->mock(get_echildren => sub { $t, $ts1, $ts2 });
    $ts1->mock(functor => sub { 'PAT' });
    $ts2->mock(functor => sub { 'ADDR' });
    $ts1->mock(get_referencing_nodes => sub { $us });

    my $uparent;
    $u->mock(set_parent => sub { $uparent = $_[1] });
    my $urel;
    $u->mock(set_relation => sub { $urel = $_[1] });

    $move->run($u, $t, undef);
    is $uparent, $us, 'move: parent';
    is $urel, 'possessor', 'move: relation';
}

{   my $add = $p->parse('!add(echild.t_lemma(concept),functor(ARG1))');
    my $u = 'Test::MockObject'->new;
    my ($ch, $relation, $concept);
    $u->mock(create_child => sub {
        $ch = 'Test::MockObject'->new;
        $ch->mock(set_functor => sub { $relation = $_[1] });
        $ch->mock(set_concept => sub { $concept  = $_[1] });
    });
    $add->run($u, undef, undef);
    is $relation, 'ARG1', 'add relation';
    is $concept, 'concept', 'add concept';
}
