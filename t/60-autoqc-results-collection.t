use strict;
use warnings;
use Test::More tests => 70;
use Test::Exception;
use Test::Warn;
use Test::Deep;
use List::MoreUtils qw/none/; 
use File::Temp qw/tempdir/;

local $ENV{'HOME'} = q[t/data];
use npg_qc::autoqc::results::qX_yield;
use npg_qc::autoqc::results::insert_size;
use npg_qc::autoqc::results::split_stats;
use npg_qc::autoqc::results::adapter;
use npg_qc::autoqc::results::tag_metrics;
use npg_qc::autoqc::results::tag_decode_stats;

use npg_qc::autoqc::qc_store::options qw/$ALL $LANES $PLEXES/;

use_ok('npg_qc::autoqc::results::collection');

my $temp = tempdir( CLEANUP => 1);

{
    my $c = npg_qc::autoqc::results::collection->new();
    isa_ok($c, 'npg_qc::autoqc::results::collection');

    my $expected = {
                    qX_yield         => 1,
                    insert_size      => 1,
                    sequence_error   => 1,
                    contamination    => 1,
                    adapter          => 1,
                    split_stats      => 1,
                    spatial_filter   => 1,
                    bcfstats         => 1,
                    gc_fraction      => 1,
                    gc_bias          => 1,
                    genotype         => 1,
                    genotype_call    => 1,
                    tag_decode_stats => 1,
                    bam_flagstats    => 1,
                    ref_match        => 1,
                    tag_metrics      => 1,
                    pulldown_metrics => 1,
                    alignment_filter_metrics => 1,
                    upstream_tags    => 1,
                    tags_reporters   => 1,
                    verify_bam_id    => 1,
                    rna_seqc         => 1,
                 };
    my $actual;
    my @checks = @{$c->checks_list};
    foreach my $check (@checks) {
      $actual->{$check} = 1;
    }
    cmp_deeply ($actual, $expected, 'checks listed');
    is(pop @checks, 'bam_flagstats', 'bam_flagstats at the end of the list');
}

{
    my $c = npg_qc::autoqc::results::collection->new();
    ok($c->is_empty, 'collection is empty');
    is($c->size, 0, 'empty collection has size 0');
    foreach my $pos ((1,5,7,2)) {
       $c->add(npg_qc::autoqc::results::qX_yield->new(position => $pos, id_run => 12, path => q[mypath]));
    }
    is($c->size(), 4, 'collection size');
    ok(!$c->is_empty(), 'collection is  not empty');
    $c->clear();
    ok($c->is_empty, 'collection is empty after clearing it');
}

{
    my $c = npg_qc::autoqc::results::collection->new();
    lives_ok {$c->sort_collection()} 'sort OK for an empty collection';
    $c->add(npg_qc::autoqc::results::qX_yield->new(position => 8, id_run => 12, path => q[mypath]));
    lives_ok {$c->sort_collection()} 'sort OK for a collection with one result';

    $c = npg_qc::autoqc::results::collection->new();
    $c->add(npg_qc::autoqc::results::qX_yield->new(position => 8, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::insert_size->new(position => 2, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::qX_yield->new(position => 6, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::insert_size->new(position => 1, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::insert_size->new(position => 8, id_run => 12, path => q[mypath]));

    $c->sort_collection();
    my $names = q[];
    foreach my $r (@{$c->results}) {
        $names .= q[ ] . $r->check_name;
    }
    is($names, q[ insert size insert size insert size qX yield qX yield], 'names in sort by name');
}

{
    my $c = npg_qc::autoqc::results::collection->new();
    $c->add(npg_qc::autoqc::results::qX_yield->new(position => 8, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::insert_size->new(position => 2, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::qX_yield->new(position => 6, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::insert_size->new(position => 1, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::insert_size->new(position => 8, id_run => 12, path => q[mypath]));

    is($c->search({position => 8, id_run => 12,})->size(), 2, 'two results are found by search');
    is($c->search({position => 8, id_run => 12, tag_index => undef, })->size(), 2, 'two results are found by search');
    is($c->search({position => 8, id_run => 12, check_name => q[qX yield],})->size(), 1, 'one result is found by search');
    is($c->search({position => 8, id_run => 12, class_name => q[qX_yield],})->size(), 1, 'one result is found by search');
    is($c->search({position => 8, id_run => 12, class_name => q[qX_yield], tag_index => undef})->size(), 1, 'one result is found by search');
    is($c->search({position => 8, id_run => 12, class_name => q[qX_yield], tag_index => 5})->size(), 0, 'no results are found by search');

    $c->add(npg_qc::autoqc::results::insert_size->new(position => 8, id_run => 12, tag_index => 5, path => q[mypath]));
    is($c->search({position => 8, id_run => 12, class_name => q[insert_size], tag_index => 5})->size(), 1, 'one result is found by search');
    is($c->search({position => 8, id_run => 12, class_name => q[qX_yield], tag_index => 5})->size(), 0, 'no results are found by search');

    $c->add(npg_qc::autoqc::results::qX_yield->new(position => 8, id_run => 12, tag_index => 5, path => q[mypath]));
    is($c->search({position => 8, id_run => 12, class_name => q[qX_yield], tag_index => 5})->size(), 1, 'one result is found by search');
    is($c->search({position => 8, id_run => 12, tag_index => undef, })->size(), 2, 'two results are found by search');
    is($c->search({position => 8, id_run => 12, tag_index => 5, })->size(), 2, 'two results are found by search');
}

{
    my $c = npg_qc::autoqc::results::collection->new();
    $c->add(npg_qc::autoqc::results::qX_yield->new(position => 8, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::insert_size->new(position => 2, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::qX_yield->new(position => 6, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::insert_size->new(position => 1, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::insert_size->new(position => 8, id_run => 12, path => q[mypath]));

    is($c->slice(q[position], 8)->size(), 2, 'two results are returned by slice by position');
    is($c->slice(q[check_name], q[insert size])->size(), 3, 'three results are returned by slice by check name');
    is($c->slice(q[class_name], q[qX_yield])->size(), 2, 'three results are returned by slice by check name');
}

{
    my @results = ();
    push @results, npg_qc::autoqc::results::qX_yield->new(position => 8, id_run => 12, path => q[mypath]);
    push @results, npg_qc::autoqc::results::qX_yield->new(position => 8, id_run => 13, path => q[mypath]);
    push @results, npg_qc::autoqc::results::qX_yield->new(position => 8, id_run => 14, path => q[mypath]);

    my $c = npg_qc::autoqc::results::collection->new();
    $c->add(npg_qc::autoqc::results::insert_size->new(position => 1, id_run => 12, path => q[mypath]));
    lives_ok {$c->add(\@results)} 'no error when adding a list ref to a collection';
    is ($c->size(), 4, 'total of 4 objects after adding an array ref');
}

{
    my $load_dir = q[t/data/autoqc/load];
    my $c = npg_qc::autoqc::results::collection->new();
    lives_ok {$c->add_from_dir($load_dir)}
       'non-autoqc json file successfully skipped';
    is($c->size(), 3, 'three results added by de-serialization');
}

{ ##### remove
  my $c = npg_qc::autoqc::results::collection->new();
  $c->add(npg_qc::autoqc::results::qX_yield->new(position => 8, id_run => 12, path => q[mypath]));
  $c->add(npg_qc::autoqc::results::insert_size->new(position => 2, id_run => 12, path => q[mypath]));
  $c->add(npg_qc::autoqc::results::qX_yield->new(position => 6, id_run => 12, path => q[mypath]));
  $c->add(npg_qc::autoqc::results::insert_size->new(position => 1, id_run => 12, path => q[mypath]));
  $c->add(npg_qc::autoqc::results::insert_size->new(position => 8, id_run => 12, path => q[mypath]));
  
  my $new_c = $c->remove(q[check_name], ['qX yield'] );
  
  is($new_c->size, 3, 'size correct');
  
  $new_c = $c->remove(q[check_name], ['qX yield', 'insert size'] );
  
  is($new_c->size, 0, 'size correct');
  
  $new_c = $c->remove(q[check_name], ['adapter'] );
  
  is($new_c->size, 5, 'size correct');
}

{
    my $c = npg_qc::autoqc::results::collection->new();
    $c->add(npg_qc::autoqc::results::qX_yield->new(   position => 8, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::split_stats->new(position => 8, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::adapter->new(    position => 8, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::adapter->new(    position => 7, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::qX_yield->new(   position => 8, id_run => 13, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::insert_size->new(position => 8, id_run => 13, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::insert_size->new(position => 6, id_run => 14, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::insert_size->new(position => 2, id_run => 14, path => q[mypath]));

    my $expected = {};
    $expected->{q[12:8]} = {position => 8, id_run => 12,};
    $expected->{q[12:7]} = {position => 7, id_run => 12,};
    $expected->{q[13:8]} = {position => 8, id_run => 13,};
    $expected->{q[14:2]} = {position => 2, id_run => 14,};
    $expected->{q[14:6]} = {position => 6, id_run => 14,};

    cmp_deeply($c->run_lane_map(), $expected, 'run-lane map generated');

    my $rlc = $c->run_lane_collections;
    my $c1 = $rlc->{q[12:8]};
    is ($c1->size, 3, 'run-lane collection size');
    $c->clear;
    is (join(q[:], $c1->get(0)->id_run, $c1->get(0)->position), q[12:8], 'correct first object');
    $c1 = $rlc->{q[14:2]};
    is ($c1->size, 1, 'run-lane collection size');
    is (join(q[:], $c1->get(0)->id_run, $c1->get(0)->position), q[14:2], 'correct first object');
}

{
    my $c = npg_qc::autoqc::results::collection->new();
    $c->add(npg_qc::autoqc::results::qX_yield->new(   position => 8, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::split_stats->new(position => 8, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::adapter->new(    position => 8, id_run => 12, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::adapter->new(    position => 8, id_run => 12, tag_index => 0, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::qX_yield->new(   position => 8, id_run => 12, tag_index => 1, path => q[mypath]));
    $c->add(npg_qc::autoqc::results::insert_size->new(position => 8, id_run => 12, tag_index => 1, path => q[mypath]));

    my $rlc = $c->run_lane_collections;
    my $c1 = $rlc->{q[12:8]};
    $c->clear;
    is ($c->size, 0, 'original collection cleared');

    is ($c1->size, 3, 'run-lane collection size');
    is (join(q[:], $c1->get(0)->id_run, $c1->get(0)->position), q[12:8], 'correct first object');

    $c1 = $rlc->{q[12:8:0]};
    is ($c1->size, 1, 'run-lane collection size');
    is (join(q[:], $c1->get(0)->id_run, $c1->get(0)->position, $c1->get(0)->tag_index,), q[12:8:0], 'correct first object');

    $c1 = $rlc->{q[12:8:1]};
    is ($c1->size, 2, 'run-lane collection size');
    is (join(q[:], $c1->get(0)->id_run, $c1->get(0)->position, $c1->get(0)->tag_index,), q[12:8:1], 'correct first object');
    is (join(q[:], $c1->get(1)->id_run, $c1->get(1)->position, $c1->get(1)->tag_index,), q[12:8:1], 'correct first object');    
}

{
    local $ENV{TEST_DIR} = q[t/data];
    my $c = npg_qc::autoqc::results::collection->new();
    my $id_run = 1234;
    $c->add_from_staging($id_run);
    is($c->size, 16, 'lane results loaded from staging area');

    $c->add_from_staging($id_run, [4]);
    is($c->size, 18, 'lane results added from staging area for lane 4');

    $c->add_from_staging($id_run, [5,6]);
    is($c->size, 22, 'lane results added from staging area for lanes 5 and 6');
}

{
    my $c = npg_qc::autoqc::results::collection->new();
    $c->add(npg_qc::autoqc::results::split_stats->new(id_run=>1, position=>1, path=>q[t]));
    $c->add(npg_qc::autoqc::results::split_stats->new(id_run=>1, position=>1, path=>q[t]));
    $c->add(npg_qc::autoqc::results::split_stats->new(id_run=>1, position=>2, path=>q[t]));
    $c->add(npg_qc::autoqc::results::split_stats->new(id_run=>1, position=>2, path=>q[t]));
    $c->add(npg_qc::autoqc::results::split_stats->new(id_run=>1, position=>3, path=>q[t], ref_name=>q[phix]));
    $c->add(npg_qc::autoqc::results::qX_yield->new(id_run=>1, position=>1, tag_index=>1, path=>q[t]));
    $c->add(npg_qc::autoqc::results::qX_yield->new(id_run=>1, position=>1, tag_index=>1, path=>q[t]));
    $c->add(npg_qc::autoqc::results::qX_yield->new(id_run=>1, position=>1, tag_index=>3, path=>q[t]));
    $c->add(npg_qc::autoqc::results::qX_yield->new(id_run=>1, position=>1, tag_index=>4, path=>q[t]));
    $c->add(npg_qc::autoqc::results::adapter->new(id_run=>1, position=>1, tag_index=>1, path=>q[t]));
    $c->add(npg_qc::autoqc::results::bam_flagstats->new(id_run=>1, position=>3, path=>q[t]));
    $c->add(npg_qc::autoqc::results::bam_flagstats->new(id_run=>1, position=>3, path=>q[t], subset => q[human]));

    my $check_names = $c->check_names;

    my @expected = ('adapter', 'qX yield', 'split stats', 'split stats phix', 'bam flagstats', 'bam flagstats human');
    is(join(q[:], @{$check_names->{list}}), join(q[:], @expected), 'check names list');
    my $expected_map = {'adapter' => 'adapter', 'qX yield' => 'qX_yield', 'split stats phix' => 'split_stats', 'split stats' => 'split_stats', 'bam flagstats'=>'bam_flagstats', 'bam flagstats human'=>'bam_flagstats',};
    cmp_deeply ($check_names->{map}, $expected_map, 'check names map');
}

{
    my $check_names = npg_qc::autoqc::results::collection->new()->check_names;
    ok (exists $check_names->{list}, 'empty collection check name list exists');
    ok (exists $check_names->{map}, 'empty collection check name map exists');
    is  (scalar @{$check_names->{list}}, 0, 'empty collection check name list is empty');
    is  (scalar keys %{$check_names->{map}}, 0, 'empty collection check name map is empty');
}

{
    local $ENV{TEST_DIR} = q[t/data];
    my $c = npg_qc::autoqc::results::collection->new();
    my $id_run = 1234;

    $c->add_from_staging($id_run, [], $PLEXES);
    is ($c->size, 0, 'asking to load plexes when there are none');

    lives_ok { $c->add_from_staging($id_run, [1,2], $ALL) }
                   'asking to load pooled lane when there are none lives';

    my $size = $c->size();
    $c->add_from_staging($id_run, [], $PLEXES);
    is ($c->size(), $size, 'collection size does not change after loading only plexes when there are none');
}

{
    my $other =  join(q[/], $temp, q[nfs]);
    mkdir $other;
    $other =  join(q[/], $other, q[sf44]);
    mkdir $other;

    `cp -R t/data/nfs/sf44/IL2  $other`;
    my $archive = join q[/], $other,
      q[IL2/analysis/123456_IL2_1234/Data/Intensities/Bustard_RTA/PB_cal/archive];
    mkdir join q[/], $archive, 'lane1';
    mkdir join q[/], $archive, 'lane2';
    mkdir join q[/], $archive, 'lane2', 'qc';
    mkdir join q[/], $archive, 'lane3';
    my $lqc = join q[/], $archive, 'lane3', 'qc';
    mkdir $lqc;
    my $file = join q[/], $archive, 'qc', '1234_3.insert_size.json';
    `cp $file $lqc`;
    mkdir join q[/], $archive, 'lane4';
    $lqc = join q[/], $archive, 'lane4', 'qc';
    mkdir $lqc;
    $file = join q[/], $archive, 'qc', '1234_4.insert_size.json';
    `cp $file $lqc`;

    local $ENV{TEST_DIR} = $temp;
    my $id_run = 1234;

    my $c = npg_qc::autoqc::results::collection->new();
    $c->add_from_staging($id_run);
    is ($c->size, 16, 'loading main qc results only');

    $c = npg_qc::autoqc::results::collection->new();
    $c->add_from_staging($id_run, undef, $PLEXES);
    is ($c->size, 2, 'loading autoqc for plexes only');

    $c = npg_qc::autoqc::results::collection->new();
    $c->add_from_staging($id_run, [1,4,6], $PLEXES);
    is ($c->size, 1, 'loading autoqc for plexes only for 3 lanes');

    $c = npg_qc::autoqc::results::collection->new();
    $c->add_from_staging($id_run, [1,6], $PLEXES);
    is ($c->size, 0, 'loading autoqc for plexes only for 2 lanes, one empty, one no-existing');

    $c = npg_qc::autoqc::results::collection->new();
    $c->add_from_staging($id_run, [1,6], $ALL);
    is ($c->size, 4, 'loading all autoqc including plexes  for 2 lanes, for plexes one empty, one no-existing');

    $c = npg_qc::autoqc::results::collection->new();
    $c->add_from_staging($id_run, [4], $ALL);
    is ($c->size, 3, 'loading all autoqc including plexes  for 1 lane');

    $c = npg_qc::autoqc::results::collection->new();
    $c->add_from_staging($id_run, [], $ALL);
    is ($c->size, 18, 'loading all autoqc');

    $c = npg_qc::autoqc::results::collection->new();
    $c->add_from_staging(234, [1,4,6], $PLEXES);
    is ($c->size, 0, 'loading autoqc for plexes only for 3 lanes');

    $c = npg_qc::autoqc::results::collection->new();
    $c->add_from_staging(234);
    is ($c->size, 0, 'nothing loaded');

    $c->add_from_dir($lqc);
    is ($c->size, 1, 'loading from directory');
    $c->add_from_dir($lqc, [], 234);
    is ($c->size, 1, 'loading from directory');
    $c->add_from_dir($lqc, [], 234);
    is ($c->size, 1, 'loading from directory');
}

1;
