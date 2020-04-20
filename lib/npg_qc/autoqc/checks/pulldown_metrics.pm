package npg_qc::autoqc::checks::pulldown_metrics;

use Moose;
use namespace::autoclean;
use English qw( -no_match_vars );
use Carp;
use File::Spec::Functions qw( catdir );
use Readonly;

extends qw(npg_qc::autoqc::checks::check);
with qw(npg_tracking::data::bait::find
        npg_common::roles::software_location
       );

our $VERSION = '0';

Readonly::Scalar my $PICARD_JAR_NAME    => q[picard.jar];
Readonly::Scalar my $PICARD_TOOL        => q[CollectHsMetrics];
Readonly::Scalar my $MAX_JAVA_HEAP_SIZE => q[3000m];
Readonly::Scalar my $PICARD_PARSE_END   => q[HISTOGRAM];
Readonly::Scalar my $COVERAGE_CAP       => 10000;
Readonly::Scalar my $MINUS_ONE          => -1;
Readonly::Scalar my $MIN_ON_BAIT_BASES_PERCENTAGE => 20;

Readonly::Hash   my %PICARD_METRICS_FIELDS_MAPPING => {
    'BAIT_TERRITORY'       => 'bait_territory',
    'TARGET_TERRITORY'     => 'target_territory',
    'TOTAL_READS'          => 'total_reads_num',
    'PF_UNIQUE_READS'      => 'unique_reads_num',
    'PF_UQ_READS_ALIGNED'  => 'unique_reads_aligned_num',
    'PF_UQ_BASES_ALIGNED'  => 'unique_bases_aligned_num',
    'ON_BAIT_BASES'        => 'on_bait_bases_num',
    'NEAR_BAIT_BASES'      => 'near_bait_bases_num',
    'OFF_BAIT_BASES'       => 'off_bait_bases_num',
    'ON_TARGET_BASES'      => 'on_target_bases_num',
    'MEAN_BAIT_COVERAGE'   => 'mean_bait_coverage',
    'MEAN_TARGET_COVERAGE' => 'mean_target_coverage',
    'FOLD_ENRICHMENT'      => 'fold_enrichment',
    'ZERO_CVG_TARGETS_PCT' => 'zero_coverage_targets_fraction',
    'HS_LIBRARY_SIZE'      => 'library_size',
                                       };

has '+file_type'         => (default => 'cram',);
has '+aligner'           => (default => 'fasta',);

has 'alignments_in_bam'  => (
	  is => 'ro',
	  isa => 'Maybe[Bool]',
	  lazy_build => 1,
);
sub _build_alignments_in_bam {
    my ($self) = @_;
    return $self->lims->alignments_in_bam;
}

has 'reference_fasta' => (
  is      => q[ro],
  isa     => q[Str | Undef],
  lazy    => 1,
  builder => q[_build_reference_fasta],
);
sub _build_reference_fasta {
  my ($self) = shift;
  return $self->refs->[0];
}

has 'coverage_cap' => (
    is      => 'ro',
    isa     => 'Str',
    default => $COVERAGE_CAP,
);

has 'max_java_heap_size' => (
    is      => 'ro',
    isa     => 'Str',
    default => $MAX_JAVA_HEAP_SIZE,
);

has 'picard_jar_path' => (
    is      => 'ro',
    isa     => 'NpgCommonResolvedPathJarFile',
    coerce  => 1,
    default => $PICARD_JAR_NAME,
);

has 'picard_command' => (
    is         => 'ro',
    isa        => 'Str',
    lazy_build => 1,
);

sub _build_picard_command {
    my $self = shift;
    my $command = $self->java_cmd . sprintf q[ -Xmx%s -jar %s %s VALIDATION_STRINGENCY=SILENT COVERAGE_CAP=%s REFERENCE_SEQUENCE=%s BAIT_INTERVALS=%s TARGET_INTERVALS=%s OUTPUT=/dev/stdout INPUT=%s],
        $self->max_java_heap_size,
        $self->picard_jar_path,
        $PICARD_TOOL,
        $self->coverage_cap,
        $self->reference_fasta,
        $self->bait_intervals_path,
        $self->target_intervals_path,
        $self->input_files->[0];
    return $command;
}

override 'can_run' => sub {
    my $self = shift;

    if($self->num_components == 1 and defined $self->composition->get_component(0)->tag_index and $self->composition->get_component(0)->tag_index == 0) {
        $self->messages->push('pulldown_metrics not run for tag#0 (no alignment)');

        return 0;
    }
    if(!$self->alignments_in_bam) {
        $self->messages->push('alignments_in_bam is false');
        return 0;
    }
    if(!$self->bait_name) {
        return 0;
    }
    return 1;
};

override 'execute' => sub {
    my ($self) = @_;

    super();

    my $can_run = $self->can_run();
    if ($self->messages->count) {
        $self->result->add_comment(join q[ ], $self->messages->messages);
    }
    if (!$can_run) { return 1; }

    if(!$self->bait_path) {
        my $ms = q[Failed to find bait interval files in repository for ] . $self->bait_name;
        $self->result->add_comment($ms);
        $self->result->pass(0);
        return 1;
    }

    $self->result->set_info( 'Aligner', qq[Picard $PICARD_JAR_NAME] );
    $self->result->set_info( 'Aligner_version', $self->current_version($self->picard_jar_path,$PICARD_TOOL) );
    $self->result->bait_path($self->bait_path);

    my $command = $self->picard_command;

    my $output;
    open my $fh, q{-|}, qq{$command} or croak qq[Cannot fork "$command". $ERRNO];
    while(<$fh>){ $output .= $_ };
    close $fh or croak qq[Cannot close pipe in __PACKAGE__ : $ERRNO, $CHILD_ERROR];
  
    my $results = $self->_parse_metrics($output);

    if($self->_interval_files_identical) {
        $self->result->interval_files_identical(1);
    } else {
        $self->result->interval_files_identical(0);
    }

    $self->_save_results($results);

    if($self->result->on_bait_bases_percent < $MIN_ON_BAIT_BASES_PERCENTAGE) {
        $self->result->pass(0);
    }

    return 1;
};

sub _parse_metrics {
    my ($self, $output) = @_;
    if (!$output) {
        croak q[No output available, cannot parse picard pulldown metrics];
    }
    my @lines = ();
    foreach my $line ( split /\n/, $output ) {
        if ( $line =~ /^\#\#\s*$PICARD_PARSE_END/smx ) { last; }
        elsif ( $line =~ /^\#/smx ) { next; }
        chomp $line;
        if ($line =~ /^\s*$/smx) { next; }
        push @lines, $line;
    }

    if (scalar @lines != 2) {
        croak q[Wrong number of result lines, should be two lines];
    }
    my @keys = split /\t/smx, $lines[0];
    my @values = split /\t/smx, $lines[1], $MINUS_ONE;
    my $num_keys = scalar @keys;
    my $num_values = scalar @values;
    if ($num_keys != $num_values) {
        croak qq[Mismatch in number of keys and values, $num_keys agains $num_values];
    }

    my $results = {};
    my $i = 0;
    while ($i < $num_keys) {
        if ($keys[$i]) {
            my $value = $values[$i] || undef;
            $results->{$keys[$i]} = $value;
        }
        $i++;
    }
    return $results;
}

sub _save_results {
    my ($self, $results) = @_;

    foreach my $key (keys %PICARD_METRICS_FIELDS_MAPPING) {
        my $value = $results->{$key};
        if (exists $PICARD_METRICS_FIELDS_MAPPING{$key}) {
            if (defined $value) {
                my $attr_name = $PICARD_METRICS_FIELDS_MAPPING{$key};
                if ($value eq q[?]) {
		                carp "Field $attr_name is set to '?', skipping...";
                } else {
                    $self->result->$attr_name($value);
                }
	          }
            delete $results->{$key};
        }
    }
    $self->result->other_metrics($results);
    return;
}

sub _interval_files_identical {
    my ($self) = @_;

    my $cmd = q[diff -q ] . $self->bait_intervals_path . q[ ] . $self->target_intervals_path . q[ 2>&1 > /dev/null];

carp q[Comparing intervals files with cmd: ], $cmd;

    if($self->bait_intervals_path and $self->target_intervals_path and system($cmd) == 0) {
        return 1;
    }

    return 0;
}

__PACKAGE__->meta->make_immutable();


1;
__END__


=head1 NAME

npg_qc::autoqc::checks::pulldown_metrics

=head1 SYNOPSIS

=head1 DESCRIPTION

    A QC check to determine whether the pulldown bait works correctly

=head1 SUBROUTINES/METHODS

=head2 new

    Moose-based.

=head2 alignments_in_bam

=head2 reference_fasta

=head2 coverage_cap

=head2 max_java_heap_size

=head2 picard_jar_path

=head2 picard_command

=head1 DIAGNOSTICS

    None.

=head1 CONFIGURATION AND ENVIRONMENT

=head1 INCOMPATIBILITIES

    None known.

=head1 BUGS AND LIMITATIONS

=head1 DEPENDENCIES

=over

=item Moose

=item namespace::autoclean

=item English

=item Carp

=item File::Spec

=item Readonly

=item npg_tracking::data::bait::find

=item npg_common::roles::software_location

=back

=head1 AUTHOR

Marina Gourtovaia E<lt>mg8@sanger.ac.ukE<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2016 GRL

This file is part of NPG.

NPG is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut
