use strict;
use warnings;
use Test::More tests => 23;
use Moose::Meta::Class;
use npg_testing::db;

use_ok('npg_qc::Schema::Result::MqcOutcomeDict');

my $schema = Moose::Meta::Class->create_anon_class(
          roles => [qw/npg_testing::db/])
          ->new_object({})->create_test_db(q[npg_qc::Schema], 't/data/fixtures', ':memory:');

my $table = 'MqcOutcomeDict';
my $final = ['Accepted final', 'Rejected final'];
my @rows = $schema->resultset($table)->search({short_desc => {'-in', $final}})->all();
is (scalar @rows, 2, 'two final outcomes');
ok ($rows[0]->is_final_outcome, 'final outcome check returns true');
ok ($rows[0]->is_accepted, 'accepted outcome check returns true');
is ($rows[0]->matching_final_short_desc(), 'Accepted final', 'matching final');
ok ($rows[0]->is_final_accepted, 'accepted & final outcome check returns true');
ok ($rows[1]->is_final_outcome, 'final outcome check returns true');
ok (!$rows[1]->is_accepted, 'accepted outcome check returns false');
ok (!$rows[1]->is_final_accepted, 'accepted & final outcome check returns false');
is ($rows[1]->matching_final_short_desc(), 'Rejected final', 'matching final');
@rows = $schema->resultset($table)->search({short_desc => {'-not_in', $final}})->all();
is (scalar @rows, 3, 'three non-final outcomes');
ok (!$rows[0]->is_final_outcome, 'final outcome check returns false');
ok ($rows[0]->is_accepted, 'accepted outcome check returns true');
is ($rows[0]->matching_final_short_desc(), 'Accepted final', 'matching final');
ok (!$rows[0]->is_final_accepted, 'accepted & final outcome check returns false');
ok (!$rows[1]->is_final_outcome, 'final outcome check returns false');
ok (!$rows[1]->is_accepted, 'accepted outcome check returns false');
ok (!$rows[1]->is_final_accepted, 'accepted & final outcome check returns false');
is ($rows[1]->matching_final_short_desc(), 'Rejected final', 'matching final');
ok (!$rows[2]->is_final_outcome, 'final outcome check returns false');
ok (!$rows[2]->is_accepted, 'accepted outcome check returns false');
ok (!$rows[2]->is_final_accepted, 'accepted & final outcome check returns false');
is ($rows[2]->matching_final_short_desc(), 'Undecided final', 'matching final');

1;