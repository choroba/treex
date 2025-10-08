#!/usr/bin/perl
use warnings;
use strict;
use utf8;

use Treex::Tool::UMR::PDTV2PB::Parser;

use Scalar::Util qw{ blessed };
use Treex::Core::BundleZone;

use Test2::V0;
plan(9);

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
    sub My::U::id { 'u00' }
    sub My::T::id { 't00' }
    my $u = bless {}, 'My::U';
    my $t = bless {}, 'My::T';
    like dies { $error->run($u, $t, {}) },
        qr{Valency transformation error: u00/t00}, 'Error';
}

{   my $setter = $p->parse('!modal-strength(neutral-negative)');
    sub My::U::set_modal_strength { $_[0]{modal_strength} = $_[1] }
    my $u = bless {}, 'My::U';
    $setter->run($u, undef, undef);
    is $u,
        hash { field(modal_strength => 'neutral-negative'); end() },
        'Setter';
}

{   my $cond = $p->parse('if(functor:PAT)(ARG1)else(ARG2)');
    sub My::T::functor { 'PAT' }
    my $t = bless {}, 'My::T';
    my $value = $cond->run(undef, $t, undef);
    is $value, 'ARG1', 'Condition';
    # TODO: Use mocking, test else.
}
