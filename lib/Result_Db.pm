# Copyright (C) 2010-2013, Benjamin Negrevergne.
package Result_Db;

use 5.012; 
use strict;
use warnings;
use Exporter 'import';
our @EXPORT = qw(result_db_init result_db_add_tuple result_db_set_result); 


use Using_Ast_Check;

our $errors = 0; 

sub error{
    die if @_ != 1; 
    print STDERR 'Error while trying to access result database: '.$_[0]."\n"; 
    $errors++;
}

sub fail_on_error{
    if($errors != 0){
	print STDERR "Cannot go further because of $errors \
    error(s) found while trying to access result database.\n";
	exit 1; 
    }
}


sub new{
    die if @_ != 3; 
    my ($class, $output_dir, $dbname) = @_;

    die if (not ($dbname =~ /[a-zA-Z_0-9]+/)) ; # prevent fancy chars in db names
    
    my $self = {
	filename => $output_dir."/.results_$dbname.txt", 
	ready => 0,
	dirty => 0, 
	fh => 0, 
	tuples => [],
    } ; 

    push @{$self->{tuples}}, tuple_format_to_string();
    bless $self, $class;
    $self->result_db_sync(); 
    fail_on_error;
    return $self; 
}


sub set_dirty{
    die if @_ != 1;

    my ($self) = @_;
    $self->{dirty} = 1; 
}


# return 1 if the data has been modified since last sync. 
sub is_dirty{
    die if @_ != 1;

    my ($self) = @_;
    return $self->{dirty}; 
}

sub ensure_db_file_open{
    die if @_ != 1;
    my ($self) = @_;
    
    if ($self->{ready} == 0){
	open my $fh, "+>".$self->{filename} or error "Cannot open db result file '".$self->{filename}."' for reading and writing: $!";
	$self->{fh} = $fh; 
	$self->{ready} = 1;
    }
    return $self->{ready}; 
}

sub close_db_file{
    die if @_ != 1;
    my ($self) = @_;
    
    close $self->{fh}; 
    $self->{ready} = 0;
}

sub result_db_sync{
    die if @_ != 1;
    my ($self) = @_;
    
    if ($self->{dirty} == 1){
	$self->ensure_db_file_open;
	foreach my $line (@{$self->{tuples}}){
	    print {$self->{fh}} $line."\n"; 
	}
	$self->close_db_file; 
    }
}

sub tuple_format_to_string{
    die if @_ != 0;
    my $format = ""; 
    foreach my $pname (Using_Ast_Check::all_parameter_names_in_std_order){
	$format .= "$pname\t"; 
    }
    return $format; 
}

# Add tuple in the result database, the result associated is set to UKN (unknown). 
# it can later be set using result_db_set_result
# Use serialize_tuple which require tuple to be in standard format (check serialize_tuple)
sub result_db_add_tuple{
    die if @_ != 2;
    my ($self, $tuple) = @_;
    
    push @{$self->{tuples}}, serialize_tuple($tuple).":UKN";
    $self->set_dirty; 
}

sub result_db_set_result{
    die if @_ != 3;
    my ($self, $tuple, $value_string) = @_;
    my $string_tuple = serialize_tuple($tuple);

    for(my $i = 0; $i < @{$self->{tuples}}; $i++){
    	my $line = $self->{tuples}[$i];
	if($line =~ s/^\Q$string_tuple\E:(.*)$/$string_tuple:$value_string/){
	    @{$self->{tuples}}[$i] = $line;
	    $self->set_dirty; 
    	    if(not ($1 eq 'UKN')){
    		error "Value '$1' found while inserting result for $value_string";
    	    }
    	}
    }
    if ($self->{dirty} != 1) {error "Cannot find database entry stub for tuple '$string_tuple'.";}
    $self->result_db_sync; 
}

# Return the result associated with a tuple.
sub get_result{
    die if @_ != 2; 
    my ($self, $tuple) = @_;
    
# FIXME tuples should be a hash table (currently tuple search is uselessly O(n)
    
    my $string_tuple = serialize_tuple($tuple); 
    foreach my $t (@{$self->{tuples}}){
	if($t =~ /\Q$string_tuple\E:(.*)/){
	    return $1; 
	}
    }
    return "UKN"; 
}

# Warning, must be in standard format (by default parameter values are
# lexicographically ordered by parameter names).
# Check  Using_Ast_Check::tuple_in_std_order for more details.
sub serialize_tuple{
    die if @_ != 1; 
    my ($tuple) = @_;
    return Using_Ast_Check::tuple_to_cannonical_string($tuple); 
}

sub unserialize_tuple{
    die if @_ != 1; 
    my ($string_tuple) = @_;
    
    die; 
}




1; 
