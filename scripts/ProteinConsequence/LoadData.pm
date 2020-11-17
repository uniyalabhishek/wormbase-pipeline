package ProteinConsequence::LoadData;

use strict;

use Wormbase;
use Data::Dumper;
use File::Path qw(remove_tree);

use base ('ProteinConsequence::BaseProteinConsequence');

sub run {
    my $self = shift;

    my $output_dir = $self->required_param('output_dir');
    my $out_file = $output_dir . '/' . $self->required_param('species') . '_mapped_alleles.ace';

    my @files = <$output_dir/*/*>;
    for my $file (@files) {
	next unless $file =~ /\.ace$/;
	my $cmd = "cat $file >> $out_file";
	my ($exit_code, $std_err, $flat_cmd) = $self->run_system_command($cmd);
	die "Combining Ace files failed [$exit_code]: $std_err" unless $exit_code == 0;    
    }

    my $wb = Wormbase->new(
	-autoace  => $self->required_param('database'),
	-organism => $self->required_param('species'),
	-debug    => $self->required_param('debug'),
	-test     => $self->required_param('test'),
	);

    $wb->load_to_database($wb->autoace, $out_file, 'WB_VEP_pipeline', $self) 
	if $self->required_param('load_to_ace');

    unless ($self->required_param('debug')) {
	opendir ( OUTPUT, $output_dir ) || die "Error in opening dir $output_dir\n";
	while(readdir(OUTPUT)) {
	    next unless $_ =~ /^Batch\d+$/;
	    my $err;
	    remove_tree($output_dir . '/' . $_, {error => \$err});
	    die "remove_tree failed for $_: " .Dumper($err) if $err && @$err;
	}
	closedir(OUTPUT);
    }

    $self->generate_report($wb);
}


sub generate_report {
    my ($self, $wb) = @_;

    my $dsn = 'dbi:mysql:database=' . lc($self->required_param('pipeline_database')) .
	';host=' . $self->required_param('pipeline_host') .
	';port=' . $self->required_param('pipeline_port');
    my $dbh = DBI->connect($dsn, $self->required_param('pipeline_user'),
			      $self->required_param('password')) or die $DBI::errstr;

    my $query = qq{
        SELECT msg FROM log_message
        WHERE msg NOT LIKE 'loop iteration%'
            AND msg NOT LIKE 'Mapping%'
            AND msg NOT LIKE 'Fetching%'
            AND msg NOT LIKE 'Creating%'
            AND msg NOT LIKE '%to go...%'
            AND msg NOT LIKE 'Writing%'
            AND msg NOT LIKE '%Discarded%'
            AND msg NOT LIKE '%stopped looping%'
            AND msg NOT LIKE '%require extra workers%'
            AND msg NOT LIKE '%gene connections%'
            AND msg NOT LIKE 'VCF_INFO%'
            AND msg NOT LIKE 'Removing insanely mapped%'
            AND msg NOT LIKE 'Extracting data for%'
            AND msg NOT LIKE 'Comparing%'
            AND msg NOT LIKE 'INFO: Mapping%'
            AND msg NOT LIKE 'Filtering%'
            AND msg NOT LIKE 'grabbing a non-virgin batch%'
        ORDER BY msg
    };

    my $log_file = $self->required_param('log_dir') . '/' . $self->required_param('species') . '_pipeline.log';
    open (LOG, '>', $log_file);
    my $errors = {};

    my $sth = $dbh->prepare($query);
    $sth->execute();
    while(my $result = $sth->fetchrow_arrayref) {
	print LOG $result->[0] . "\n";
	$errors = process_log_message($errors, $result->[0]);
    }

    close (LOG);

    
    my %error_msgs = ( 
	not_live                  => 'variants not mapped as not Live',
	no_flanks                 => 'variants not mapped due to missing both flanking sequences',
	no_left_flank             => 'variants not mapped due to missing left flanking sequence',
	no_right_flank            => 'variants not mapped due to missing right flanking sequence',
	short_flanks              => 'variants not mapped due to both flanks being < 10bp',
	n_in_flank                => 'variants not mapped due to Ns in flanking sequences',
	no_type                   => 'variants skipped due to no Type_of_mutation',
	moved                     => 'variants moved to a different target sequence during mapping',
	map_failed                => 'variants that could not be mapped',
	too_big                   => 'deletions too large for VEP analysis',
	sub_indel                 => 'variants ignored by VEP due to substitution defined with inDel',
	missing_from_to           => 'variants ignored by VEP due to missing FROM/TO fields',
	non_standard_substitution => 'variants ignored by VEP due to non-standard substitution',
	non_standard_insertion    => 'variants ignored by VEP due to non-standard insertion',
	non_sub_indel             => 'variants ignored by VEP as not mutation type not substitution/insertion/deletion',
	no_allele                 => 'variants ignored by VEP as no allele defined',
	geneace_only              => 'variant/gene connections only present in GeneAce',
	new_connection            => 'variant/gene connections created in this build',
	other                     => 'Other warnings/errors'
	);

    my $summary_file = $self->required_param('log_dir') . '/' . $self->required_param('species') . '_summary.log';
    open (SUMMARY, '>', $summary_file);
    print SUMMARY 'The WormBase VEP Pipeline for ' . $self->required_param('database') . ' has completed.  A summary of ' .
	'errors/warnings generated is given below.  The full log file can be found at ' . 
	$self->required_param('log_file') . '.  Warnings produced by the EnsEMBL VEP can be found at ' . 
	$self->required_param('vep_warning_file') . ".\n\n\n";
    
    for my $err ('not_live', 'no_flanks', 'no_left_flank', 'no_right_flank', 'short_flanks', 'n_in_flank', 'no_type',
		 'moved', 'map_failed', 'too_big', 'sub_indel', 'non_standard_substitution', 'non_standard_insertion',
		 'non_sub_indel', 'no_allele', 'geneace_only', 'new_connection') {
	print SUMMARY $errors->{$err} . ' ' . $error_msgs{$err} . "\n\n" if exists $errors->{$err};
    }
    print SUMMARY scalar @{$errors->{'other'}} . " other warnings/errors:\n" .
	    join("\n", sort @{$errors->{'other'}}) . "\n\n" if exists $errors->{'other'};
    
		 close (SUMMARY);
    
    $wb->mail_maintainer('WormBase VEP Pipeline Report', 'mark.quintontulloch@wormbase.org', $summary_file);

    my $vep_warning_file = $self->required_param('log_dir') . '/' . $self->required_param('species');
    my $cmd = 'cat ' . $self->required_param('output_dir') . '/Batch*/*_warnings.txt > ' . $vep_warning_file;
    my ($exit_code, $stderr, $flat_cmd) = $self->run_system_command($cmd);
    
    
    return;
}


sub process_log_message {
    my ($errors, $msg) = @_;

    my (%geneace_only, %new_connections);

    if ($msg =~ /^WARNING: \S+ \(.+\) is not Live/) {
	$errors->{'not_live'}++;
    }
    elsif ($msg =~ /^ERROR: \S+ \(.+\) has missing Mapping_target/) {
	$errors->{'no_map_target'}++;
    }
    elsif ($msg =~ /^ERROR: \S+ \(.+\) has no\/empty Flanking_sequence/) {
	$errors->{'no_flanks'}++;
    }
    elsif ($msg =~ /^ERROR: \S+ \(.+\) has no left Flanking_sequence/) {
	$errors->{'no_left_flank'}++;
    }
    elsif ($msg =~ /^ERROR: \S+ \(.+\) has no right Flanking_sequence/) {
	$errors->{'no_right_flank'}++;
    }
    elsif ($msg =~ /^ERROR: \S+ \(.+\) has Ns in flanks/) {
	$errors->{'n_in_flank'}++;
    }
    elsif ($msg =~ /^WARNING: \S+ \(.+\) has no Type_of_mutation/) {
	$errors->{'no_type'}++;
    }
    elsif ($msg =~ /^WARNING: \S+ has at least both flanks < 10/) {
	$errors->{'short_flanks'}++;
    }
    elsif ($msg =~ /^WARNING: moved \S+ \(/) {
	$errors->{'moved'}++;
    }
    elsif ($msg =~ /^ERROR: Failed to map \S+ and will not attempt/) {
	$errors->{'map_failed'}++;
    }
    elsif ($msg =~ /^WARNING: \S+ \- Deletion bigger than maximum/) {
	$errors->{'too_big'}++;
    }
    elsif ($msg =~ /^WARNING: \S+ \- Substitution defined together with/) {
	$errors->{'sub_indel'}++;
    }
    elsif ($msg =~ /^WARNING: \S+ \- [Ss]ubstitution has missing\/empty FROM/) {
	$errors->{'missing_from_to'}++;
    }
    elsif ($msg =~ /^WARNING: \S+ \- small substitution has numbers/) {
	$errors->{'non_standard_substitution'}++;
    }
    elsif ($msg =~ /^WARNING: \S+ \- Mutation type not substitution, deletion, or insertion/) {
	$errors->{'non_sub_indel'}++;
    }
    elsif ($msg =~ /^WARNING: \S+ \- Non\-standard insertion/) {
	$errors->{'non_standard_insertion'}++;
    }
    elsif ($msg =~ /^WARNING: \S+ \- No allele defined/) {
	$errors->{'no_allele'}++;
    }
    elsif ($msg =~ /^ERROR: \S+ \(.+\) \-> \S+ connection is only in geneace/) {
	$errors->{'geneace_only'}++;
    }
    elsif ($msg =~ /^INFO: \S+ \-> \S+ connection created by script/) {
	$errors->{'new_connection'}++;
    }
    else {
	push @{$errors->{'other'}}, $msg;
    }

    
    return $errors;
}

1;

