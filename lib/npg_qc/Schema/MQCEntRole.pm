package npg_qc::Schema::MQCEntRole;

use Moose::Role;
use DateTime;
use DateTime::TimeZone;
use Carp;
use Readonly;

our $VERSION = '0';

Readonly::Scalar my $MQC_LIB_LIMIT    => 50;

requires 'short_desc';
requires 'mqc_outcome';
requires 'update';
requires 'insert';
requires 'historic_resultset';

Readonly::Hash my %DELEGATION_TO_MQC_OUTCOME => {
  'has_final_outcome' => 'is_final_outcome',
  'is_accepted'       => 'is_accepted',
  'is_final_accepted' => 'is_final_accepted',
  'is_undecided'      => 'is_undecided',
};

foreach my $this_class_method (keys %DELEGATION_TO_MQC_OUTCOME ) {
  __PACKAGE__->meta->add_method( $this_class_method, sub {
      my $self = shift;
      my $that_class_method = $DELEGATION_TO_MQC_OUTCOME{$this_class_method};
      return $self-> mqc_outcome->$that_class_method;
    }
  );
}

around [qw/update insert/] => sub {
  my $orig = shift;
  my $self = shift;
  $self->last_modified($self->get_time_now);
  my $return_super = $self->$orig(@_);

  $self->_create_historic();
  return $return_super;
};

sub get_time_now {
  return DateTime->now(time_zone => DateTime::TimeZone->new(name => q[local]));
}

sub mqc_lib_limit {
  return $MQC_LIB_LIMIT;
}

sub data_for_historic {
  my $self = shift;
  my $my_cols = {$self->get_columns};
  my @hist_cols = $self->result_source
                       ->schema
                       ->source($self->historic_resultset)
                       ->columns;
  my $vals = {};
  foreach my $x (@hist_cols) {
    if ( exists $my_cols->{$x} ) {
      $vals->{$x} = $my_cols->{$x};
    }
  }
  return $vals;
}

sub validate_username {
  my ( $self, $username ) = @_;

  if(!defined $username){
    croak q[Mandatory parameter 'username' missing in call];
  }
  if ($username =~ /^\d+$/smx) {
    croak "Have a number $username instead as username";
  }
  return;
}

sub update_outcome {
  my ($self, $outcome, $username) = @_;

  if(!defined $outcome){
    croak q[Mandatory parameter 'outcome' missing in call];
  }
  $self->validate_username($username);
  my $outcome_dict_obj = $self->find_valid_outcome($outcome);

  my $outcome_id = $outcome_dict_obj->id_mqc_outcome;
  #There is a row that matches the id_run and position
  if ($self->in_storage) {
    #Check if previous outcome is not final
    if($self->has_final_outcome) {
      croak(sprintf 'Error: Outcome is already final but trying to transit to %s.',
            $self->short_desc);
    } else { #Update
      my $values = {};
      $values->{'id_mqc_outcome'} = $outcome_id;
      $values->{'username'}       = $username;
      $values->{'modified_by'}    = $username;
      $self->update($values);
    }
  } else { #Is a new row just insert.
    $self->id_mqc_outcome($outcome_id);
    $self->username($username);
    $self->modified_by($username);
    $self->insert();
  }
  return 1;
}

#Create and save historic from the entity current data.
sub _create_historic {
  my $self = shift;
  my $rs = $self->result_source->schema->resultset($self->historic_resultset);
  my $historic = $rs->create($self->data_for_historic);
  return 1;
}

#Fetches valid outcome object from the database.
sub find_valid_outcome {
  my ($self, $outcome) = @_;

  my $rs = $self->result_source->schema->resultset('MqcOutcomeDict');
  my $outcome_dict;
  if ($outcome =~ /\d+/xms) {
    $outcome_dict = $rs->find($outcome);
  } else {
    $outcome_dict = $rs->search({short_desc => $outcome})->next;
  }
  if (!(defined $outcome_dict) || !$outcome_dict->iscurrent) {
    croak(sprintf 'Error: Not possible to transit %s to a non-existing outcome "%s".',
          $self->short_desc, $outcome);
  }
  return $outcome_dict;
}

no Moose::Role;

1;

__END__


=head1 NAME

  npg_qc::Schema::MQCEntRole

=head1 SYNOPSIS


=head1 DESCRIPTION

  Common method for lane and library manual qc outcome DBIx objects.

=head1 SUBROUTINES/METHODS

=head2 get_time_now

=head2 mqc_lib_limit

=head2 data_for_historic

  Looks at the entity columns and the matching historic metadata to
  find those columns which intersect and copies from entity to a new
  hash intersecting values.

=head2 validate_username

  To make sure the username is alphanumeric

=head2 update_outcome

  Updates the outcome of the entity with values provided.

  $obj->($outcome, $username)

=head2 has_final_outcome

  Returns true id this entry corresponds to a final outcome, otherwise returns false.

=head2 is_accepted

  Returns the result of checking if the outcome is considered accepted. Delegates the 
  check to L<npg_qc::Schema::Result::MqcOutcomeDict>

=head2 is_final_accepted

  Returns the result of checking if the outcome is considered final and accepted. 
  Delegates the check to L<npg_qc::Schema::Result::MqcOutcomeDict>

=head2 is_undecided

  Returns true if the current outcome is undecided. 
  Delegates the check to L<npg_qc::Schema::Result::MqcOutcomeDict>

=head2 find_valid_outcome

  Finds the MqcOutcomeDict entity that matches the outcome. Or nothing if there is
  no valid outcome matching the parameter.

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

=head1 DEPENDENCIES

=over

=item Moose::Role

=item DateTime

=item DateTime::TimeZone

=item Readonly

=item Carp

=back

=head1 INCOMPATIBILITIES

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

Jaime Tovar <lt>jmtc@sanger.ac.uk<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2015 Genome Research Ltd

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
