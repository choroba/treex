#!/usr/bin/perl
use warnings;
use strict;

use Treex::Tool::UMR::PDTV2PB::Parser;

use Test2::V0;
plan(4);

my $p = 'Treex::Tool::UMR::PDTV2PB::Parser'->new;
ok $p, 'Instantiates';
like ${ $p->dsl }, qr/ Rule \s+ ::= /x, 'Has a DSL';
ok $p->grammar, 'Has a grammar';

is $p->parse('!delete'),
    [Rule => [Commands => [Command => [No_args => 'delete']]]], 'Parses delete';
