package ElasticSearchDemo::Form::User::Profile;
use HTML::FormHandler::Moose;
use namespace::autoclean;
extends 'HTML::FormHandler';

has '+name' => ( default => 'profile_form' );

has_field 'first_name' => (
    label            => 'First name',
    type             => 'Text',
);
 
has_field 'last_name' => (
    label            => 'Last name',
    type             => 'Text',
);
 
has_field 'affiliation' => (
    label            => 'Affiliation',
    type             => 'Text',
);

has_field 'email' => (
    label            => 'Email',
    type             => 'Email',
    required         => 1,
    required_message => 'Please enter the contact email.',
);

has_field 'password' => (
    label            => 'Password',
    type             => 'Password',
    required         => 1,
    required_message => 'Please enter your password.',
    minlength        => 5
);

has_field 'password_conf' => (
    label            => 'Password (again)',
    type             => 'Password',
    required         => 1,
    required_message => 'Confirm your password.',
    minlength        => 5
);

sub validate {
  my $self = shift;

  if ($self->field('password_conf')->value ne
      $self->field('password')->value )
    {
      $self->field('password_conf')
	->add_error('Passwords do not match. Please try again.');
    }
};
    
has_field 'submit'  => ( type => 'Submit', value => 'Update', element_class => ['btn'] );

__PACKAGE__->meta->make_immutable;

no HTML::FormHandler::Moose;

1;
