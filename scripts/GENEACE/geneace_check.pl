#!/usr/local/bin/perl5.8.0 -w
# 
# geneace_check.pl
#
# Initiated by Keith Bradnam
#
# Script to run consistency checks on the geneace database
#
# Last updated by: $Author: krb $
# Last updated on: $Date: 2004-06-23 09:45:09 $

use strict;
use lib -e "/wormsrv2/scripts" ? "/wormsrv2/scripts" : $ENV{'CVS_DIR'};
use Wormbase;
use Ace;
use Ace::Object;
use Carp;
use Getopt::Long;
use GENEACE::Geneace;

###################################################
# Miscellaneous important variables               # 
###################################################

my $tace = glob("~wormpub/ACEDB/bin_ALPHA/tace");          # tace executable path
my $curr_db = "/nfs/disk100/wormpub/DATABASES/current_DB"; # Used for some cross checking with geneace
my $def_dir = "/wormsrv1/geneace/wquery";                  # where lots of table-maker definitions are kept
my $test_def_dir ="/nfs/disk100/wormpub/ck1";             # where lots of table-maker definitions are kept for running this script not on wormsrv2
my $machine = ();
$machine = "+" if `ls /wormsrv1/`;                         # if sees wormsrv1 then $machine is defined, else it remains undef: for running on cbi1, eg

my $rundate = `date +%y%m%d`; chomp $rundate;              # Used by various parts of script for filename creation
my $maintainers = "All";                                   # Default for emailing everyone logfile
my $caltech_errors = 0;                                    # counter for tracking errors going into Caltech email
my $jah_errors = 0;                                        # counter for tracking errors going into Caltech email
my $log;                                                   # main log file for most output
my $caltech_log;                                           # Additional log file for problems that need to be sent to Caltech
my $jah_log;                                               # Additional log file for problems to be sent to Jonathan Hodgkin at CGC
my (%L_name_F_WBP, %L_name_F_M_WBP);                       # hashes for checking Person and Author merging?

###################################################
# command line options                            # 
###################################################

my ($help, $debug, $class, @classes, $database, $ace, $verbose);

GetOptions ("h|help"        => \$help,
            "d|debug=s"     => \$debug,
	    "c|class=s"     => \@classes,
	    "db|database=s" => \$database,
            "a|ace"         => \$ace,
	    "v|verbose"     => \$verbose
           );

#print @classes, "\n" if ($classes[0] eq lc("ps") || $classes[0] eq lc("pseudo"));

#__END__
##################################################
# other variables                                #
##################################################

# Display help if required
if ($help){&usage("Help")}

# Use debug mode?
if($debug){
  print "\nDEBUG = \"$debug\"\n";
  ($maintainers = "$debug" . '\@sanger.ac.uk');
}

# choose database to query: default is /wormsrv1/geneace
my $default_db = "/wormsrv1/geneace";
($default_db = $database) if ($database);
print "\nUsing $default_db as default database.\n\n";

# Open file for acefile output?
my $acefile;
if ($ace){
  $acefile = "/wormsrv1/geneace/CHECKS/geneace_check.$rundate.$$.ace" if $machine;
  $acefile = "/nfs/disk100/wormpub/tmp/geneace_check.$rundate.ace" if !$machine;
  open(ACE, ">>$acefile") || croak $!;
  system("chmod 777 $acefile");
}

my $next_build_ver = get_wormbase_version() + 1 ; # next build number

# Set up other log files
&create_log_files;


######################################################################################################
######################################################################################################
##                                                                                                  ##
##                                       MAIN PART OF SCRIPT                                        ##
##                                                                                                  ##
######################################################################################################
######################################################################################################

# open a connection to database
my $db = Ace->connect(-path  => $default_db,
		      -program =>$tace) || do { print LOG "Connection failure: ",Ace->error; die();};


my $ga = init Geneace();
# hash for converting locus/seq. names <-> gene_id
my @Gene_info = $ga -> gene_info($default_db, "seq2id");
my %Gene_info = %{$Gene_info[0]};
my %seqs_to_gene_id = %{$Gene_info[1]};

# counters used later
my $non_CGC_to_seq = 0;
my $non_CGC_non_seq = 0;

# Process separate classes if specified on the command line else process all classes, EXCEPT "pseudo", see
# /wormsrv1/geneace/JAH_DATA/MULTI_PT_INFERRED/README for detailed description
@classes = ("gene", "laboratory", "evidence", "allele", "strain", "rearrangement", "mapping", "xref", "multipt") if (!@classes);

foreach $class (@classes){
  if ( $class =~ m/gene/i )                {&process_gene_class}
  if ( $class =~ m/laboratory|lab/i )      {&process_laboratory_class}
  if ( $class =~ m/evidence|evi/i )        {&check_evidence}
  if ( $class =~ m/allele/i )              {&process_allele_class}
  if ( $class =~ m/strain/i )              {&process_strain_class}
  if ( $class =~ m/rearrangement|rearr/i ) {&process_rearrangement}
  if ( $class =~ m/mapping/i )             {&check_genetics_coords_mapping}
  if ( $class =~ m/xref/i )                {&check_bogus_XREF}
  if ( $class =~ m/multipt|mui/i )         {&check_dubious_multipt_gene_connections}

  # this will not fire off even if no class is specified see also http://intweb.sanger.ac.uk/Projects/C_elegans/DOCS/geneace_duties.shtml
  # section "Load CGC approved pseudo genetic markers to geneace before at start of a build"
  if ( $class =~ m/pseudo|ps/i )           {&int_map_to_map_loci}
}

#######################################
# Tidy up and mail relevant log files #
#######################################

$db->close;
close(LOG);
close(CALTECHLOG);
close(JAHLOG);
close(ACE) if ($ace);


# Always mail to $maintainers (which might be a single user under debug mode)
mail_maintainer($0,$maintainers,$log);


# Also mail to Erich unless in debug mode or unless there is no errors
my $interested ="krb\@sanger.ac.uk, emsch\@its.caltech.edu, kimberly\@minerva.caltech.edu";
mail_maintainer($0,"$interested",$caltech_log) unless ($debug || $caltech_errors == 0);


# Email Jonathan Hodgkin subset of errors that he might be able to help with unless
# in debug mode or no errors
mail_maintainer($0,"cgc\@wormbase.org, jonathan.hodgkin\@bioch.ox.ac.uk",$jah_log) unless ($debug || $jah_errors == 0);

mail_maintainer("Pseudo genetic marker(s) to approve for WS$next_build_ver", "cgc\@wormbase.org, jonathan.hodgkin\@bioch.ox.ac.uk", $jah_log) if ($classes[0] eq lc("ps") || $classes[0] eq lc("pseudo"));


exit(0);

#--------------------------------------------------------------------------------------------------------------------

                          ###########################################################
                          #             SUBROUTINES FOR -c gene option              #
                          ###########################################################

sub process_gene_class{

  # get all genes
  my @gene_ids = $db->fetch(-class => 'Gene',
	                    -name  => '*');

  # Loop through loci checking for various potential errors in the Locus object
  print "Checking Gene class for errors:\n";
  print LOG "\nChecking Gene class for errors:\n--------------------------------\n";

  foreach my $gene_id (@gene_ids){
    # useful to see where you are in the script if running on command line
    if ($verbose){
      print "$gene_id: $Gene_info{$gene_id}{'Public_name'}";
    }
    my $warnings;

    ($non_CGC_to_seq, $non_CGC_non_seq) = &test_locus_for_errors($gene_id);
    print "\n" if ($verbose);
  }
  
  print LOG "INFO: $non_CGC_to_seq gene id(s) linked to sequence but not linked to CGC_name\n" if $non_CGC_to_seq > 0;
  print LOG "INFO: $non_CGC_non_seq gene id(s) NOT linked to sequence AND CGC_name\n" if $non_CGC_non_seq > 0;

  # looks for seq. (predictted_gene, transcript) link to an allele, but which gene ids don't => make gene id -> allele connection
  &link_seq_to_Gene_based_on_allele($db);

  # Find sequences (CDS/Trans/Pseudo) linkd to multiple gene_ids
  print "Looking for sequences (CDS/Trans/Pseudo) connected to multiple gene ids\n" if ($verbose);
  &find_seqs_with_multiple_Gene_ids($db);

  # check highest gene id number = gene obj. number
  my $last_gene_id = $gene_ids[-1];
  $last_gene_id =~ s/WBGene(0)+//;
  
  if ( scalar @gene_ids != $last_gene_id ){
    print LOG "ERROR 25: The highest gene id ($last_gene_id) is not equal to total number of Gene objects (", scalar @gene_ids, ")";
  }

  # checks gene_id that does not have a map position nor an interpolated_map_position with conditions in the query
  my $map_query = "Find gene * where !(map | interpolated_map_position) & (cds|transcript|pseudogene) & species=\"*elegans\" & !sequence_name=\"MTCE*\"";
  push(my @gene_id_has_no_map_info, $db->find($map_query));
  foreach my $e (@gene_id_has_no_map_info){
    print LOG "ERROR 26: $e has neither Map nor Interpolated_map_position info\n";
  }
}

sub test_locus_for_errors{
  my $gene_id = shift;
  my $warnings;

  # check existence of Gene version
  if ( !defined $gene_id->Version ){
    $warnings .= "ERROR 1: $gene_id ($Gene_info{$gene_id}{'Public_name'}) has no Version number\n";
    print "." if ($verbose);
  }

  # check the number of version and Version_change of a Gene is identical
  if ( defined $gene_id->Version && defined $gene_id->Version_change ){
    my @ver_changes = $gene_id->Version_change;
    my $ver = $gene_id->Version;
    if ( "$ver" ne "$ver_changes[-1]" ){
      $warnings .= "ERROR 2: $gene_id ($Gene_info{$gene_id}{'Public_name'}) has Version problem: current ($ver) => history ($ver_changes[-1])\n";
      print "." if ($verbose);
    }
  }

  # test for Other_name tag but no value
  if ( defined($gene_id->at('Name.Other_name')) && !defined $gene_id->Other_name ){
    $warnings .= "ERROR 3: $gene_id ($Gene_info{$gene_id}{'Public_name'}) has 'Other_name' tag without value\n";
    print "." if ($verbose);
  }

  # test for Public_name is different from CGC_name
  if ( defined $gene_id->CGC_name && defined $gene_id->Public_name ){				
    my $cgc_name = $gene_id->CGC_name;
    my $pub_name = $gene_id->Public_name;
    if ( $cgc_name ne $pub_name ){
      $warnings .= "ERROR 5(a): $gene_id ($Gene_info{$gene_id}{'CGC_name'}) has a Public_name ($pub_name) different from its CGC_name ($cgc_name)\n";
      if ($ace){
	print ACE "\nGene : \"$gene_id\"\n";
	print ACE "Public_name \"$Gene_info{$gene_id}{'CGC_name'}\"\n";
      }
    }
    print "." if ($verbose);
  }

  # test for missing Public_name and assign one if so
  if( !defined $gene_id->Public_name && (defined $gene_id->CGC_name || defined $gene_id->Sequence_name || defined $gene_id->Other_name) ){
    $warnings .= "ERROR 6(a): $gene_id ($Gene_info{$gene_id}{'CGC_name'}) has no Public_name but has CGC/Sequence/Other_name\n";
    if ($ace){
      print ACE "\nGene : \"$gene_id\"\n";
      print ACE "Public_name \"$Gene_info{$gene_id}{'CGC_name'}\"\n" if exists $Gene_info{$gene_id}{'CGC_name'};
      print  "Public_name \"$Gene_info{$gene_id}{'CGC_name'}\"=== E6\n" if exists $Gene_info{$gene_id}{'CGC_name'};
      print ACE "Public_name \"$Gene_info{$gene_id}{'Sequence_name'}\"\n" if !exists $Gene_info{$gene_id}{'CGC_name'} && exists $Gene_info{$gene_id}{'Sequence_name'};
      if ( !exists $Gene_info{$gene_id}{'CGC_name'} && !exists $Gene_info{$gene_id}{'Sequence_name'} && exists $Gene_info{$gene_id}{'Other_name'} ){
	print ACE "Public_name \"$Gene_info{$gene_id}{'Other_name'}\"\n"
      }
    }
    print "." if ($verbose);
  }

  if( !defined $gene_id->Public_name && !defined $gene_id->CGC_name && !defined $gene_id->Sequence_name && !defined $gene_id->Other_name ){
    $warnings .= "ERROR 6.1: $gene_id (?) has no Public_name as there is no CGC_/Sequence_/Other_name\n";
    print "." if ($verbose);
  }

  # test for discrepancy betw. CGC_name and Gene_class name, ie, for aap-1, the gene_class should be aap
  # The idea is that when two Gene objects are merged, the latter one will overwrite the first one, as the gene_class field is UNOQUE

  if( defined $gene_id->Gene_class && defined $gene_id->CGC_name ){
    my $cgc_name = $gene_id->CGC_name;
    my $gc_name = $cgc_name;
    $gc_name =~ s/-.+//;
    my $gc = $gene_id->Gene_class;

    if ($gc ne $gc_name){
      $warnings .= "ERROR 7: $gene_id ($cgc_name) has incorrect Gene_class $gc\n";
      print "." if ($verbose);
    }
  }

  # checks that when a Gene belongs to a Gene_class, it should have a CGC_name
  if ( defined $gene_id->Gene_class && !defined $gene_id->CGC_name ){
    my $gc = $gene_id->Gene_class;
    $warnings .= "ERROR 8: $gene_id ($Gene_info{$gene_id}{'Public_name'}) has no CGC_name but links to Gene_class $gc\n";
    print "." if ($verbose);
  }

  # checks a CGC name is linked to a sequence but not yet to a CGC_name 
  if ( !defined $gene_id->CGC_name && $gene_id->Sequence_name && $gene_id->Species =~ /elegans/ ){
    $non_CGC_to_seq++;
    print "." if ($verbose);
  }

  # checks a gene id is linked neither to a sequence nor a CGC name
  if ( !$gene_id->CGC_name && !$gene_id->Sequence_name && $gene_id->Species =~ /elegans/ ){
    $non_CGC_non_seq++;
    print "." if ($verbose);
  }

  # checks existence of a CGC name but no gene_class
  if ( defined $gene_id->CGC_name && !defined $gene_id->Gene_class ){
    my $cgc_name = $gene_id->CGC_name;
    $warnings .= "ERROR 10: $gene_id has CGC name ($cgc_name) but is not linked to its Gene_class\n";
    print "." if ($verbose);
    print JAHLOG "ERROR 10: $gene_id has CGC name ($cgc_name) but is not linked to its Gene_class\n";
  }

  # test for missing Species tag
  if ( !defined $gene_id->Species ){
    $warnings .= "ERROR 11(a) $gene_id ($Gene_info{$gene_id}{'CGC_name'}) has no 'Species' info\n";
    print "." if ($verbose);
    if ($ace){
      print ACE "\n\nGene : \"$gene_id\"\n";
      if ( $Gene_info{$gene_id}{'Public_name'} !~ /^Cb-|^Cr-|^Cv-/ ){
        print ACE "Species \"Caenorhabditis elegans\"\n";
      }
      if ( $Gene_info{$gene_id}{'Public_name'} =~/^Cb-.+/ ){
        print ACE "Species \"Caenorhabditis briggsae\"\n";
      }
      if ( $Gene_info{$gene_id}{'Public_name'} =~/^Cr-.+/ ){
        print ACE "Species \"Caenorhabditis remanei\"\n";
      }
      if ( $Gene_info{$gene_id}{'Public_name'} =~/^Cv-.+/ ){
        print ACE "Species \"Caenorhabditis vulgaris\"\n";
      }
    }
  }

  # test for Map tag and !NEXT
  if ( $gene_id->at('Map_info.Map') && !defined $gene_id->Map ){
    $warnings .= "ERROR 12: $gene_id ($Gene_info{$gene_id}{'Public_name'}) has a 'Map' tag without a value\n";
    print "." if ($verbose);
  }
  if ( $gene_id->at('Map_info.Interpolated_map_position') && !defined $gene_id->Interpolated_map_position ){
    $warnings .= "ERROR 12.1: $gene_id ($Gene_info{$gene_id}{'Public_name'}) has an 'Interpolated_map_position' tag without a value\n";
    print "." if ($verbose);
  }


  # test for CDS/Transcript/Pseudogene/Other_sequence tag and no value
  foreach my $tag ("CDS", "Transcript", "Pseudogene", "Other_sequence"){
    if( defined $gene_id->at('Molecular_info.$tag') && !defined $gene_id->$tag ){
      $warnings .= "ERROR 13(a): $gene_id ($Gene_info{$gene_id}{'Public_name'}) has '$tag' tag but no associated value\n";
      print "." if ($verbose);
      if ($ace){print ACE "\n\nGene : \"$gene_id\"\n"; print ACE "-D $tag\n"}
    }
  }

  # checks that for each CDS/Transcript/Pseudogene tag, if linked to multiple sequences, they should be splice variants of a same gene
  foreach my $tag ("CDS", "Transcript", "Pseudogene"){
    if( defined $gene_id->$tag ){
      my @iso = $gene_id->$tag;
      my %variants;
      if (scalar @iso > 1){
	foreach (@iso){
	  if ( $_ =~ /((.+)\..+)/ ){
	    $variants{$2}=$1 if !exists $variants{$_};
	  }
	}
      }
      my @diff = values %variants;
      $warnings .= "ERROR 14: $gene_id ($Gene_info{$gene_id}{'Public_name'}) has '$tag' tag populated with different genes: @diff\n" if scalar @diff > 1;
      print "." if ($verbose);
    }
  }

  # check that live gene id should not have wpxxx appended to its Sequence_name or CDS/Transcript/Pseudogene
  foreach my $tag ("Sequence_name", "CDS", "Transcript", "Pseudogene", "Public_name"){
    #if ( $gene_id->$tag =~ /.+\:wp\d+/ && defined $gene_id->$tag && $gene_id->at('Identity.Live') ){
    if ( defined $gene_id->$tag && $gene_id->at('Identity.Live') ){
      my $history = $gene_id->$tag;
      if ( $history =~ /:wp\d+/ ){
	$warnings .= "ERROR 15: $gene_id has $tag with :wpxxx history name appended\n";
	print "." if ($verbose);
      }
    }
  }
  # test for CDS or Transcript or Pseudogene AND !Sequence_name
  foreach my $tag ("CDS", "Transcript", "Pseudogene"){	
    if( defined $gene_id->$tag && !defined $gene_id->Sequence_name ){
      my $seq = $gene_id->$tag;
      $warnings .= "ERROR 16(a): $gene_id ($Gene_info{$gene_id}{'Public_name'}) has a '$tag' tag but not a 'Sequence_name' tag\n";
      print "." if ($verbose);
      if ($ace){
        print ACE "\nGene : \"$gene_id\"\n";
        if ($seq =~ /(.+\.\d+)\w/){         # ignore splice variants for Sequence_name
	  $seq = $1;
	  print ACE "Sequence_name \"$seq\"\n";
        }
        else {
	  print ACE "Sequence_name \"$seq\"\n"; # eg, x.t1 or B0334.1
        }
      }
    }
  }

  # test for Sequence_name AND !(CDS or Transcript or Pseudogene)
  if( defined $gene_id->Sequence_name && !defined $gene_id->CDS && !defined $gene_id->Transcript && !defined $gene_id->Pseudogene ){
    $warnings .= "ERROR 17: $gene_id ($Gene_info{$gene_id}{'Public_name'}) has a Sequence_name but is not linked to a sequence\n";
    print "." if ($verbose);
  }

  # test for CDS/Transcript/Pseudogene (ignore variants if so) = Sequence_name
  foreach my $tag ("CDS", "Transcript", "Pseudogene"){
    if( defined $gene_id->$tag && defined $gene_id->Sequence_name ){
      my $seq = $gene_id->$tag;
      my $seq_name = $gene_id->Sequence_name;
      if ($seq =~ /(.+\.\d+)[a-z]/){         # ignore splice variants for Sequence_name
        $seq = $1;
      }
      # compare $seq with $name for difference
      if ($seq ne $seq_name){
        $warnings .= "ERROR 18: $gene_id ($Gene_info{$gene_id}{'Public_name'}) has a $tag ($seq) different from its Sequence_name ($seq_name)\n";
        print "." if ($verbose);
      }
    }
  }

  # test for CDS AND Pseudogene tags both present
  if( defined $gene_id->at('Molecular_info.CDS') && defined $gene_id->at('Molecular_info.Pseudogene') ){
    $warnings .= "CHECK: $gene_id has both 'CDS' tag AND 'Pseudogene' tag\n";
    print "." if ($verbose);
  }

  # test for Pseudogene AND Transcript tags both present
  if( defined $gene_id->at('Molecular_info.Pseudogene') && defined $gene_id->at('Molecular_info.Transcript') ){
    $warnings .= "CHECK: $gene_id has both 'Pseudogene' tag AND 'Transcript' tag\n";
    print "." if ($verbose);
  }

  # Look for Genes with no Positive_clone info but which can be derived from its sequence info
  foreach my $tag ("CDS", "Transcript", "Pseudogene"){
    if( !defined $gene_id->Positive_clone(1) && defined $gene_id->$tag(1) ){
      my $seq = $gene_id->$tag(1);

      # need to chop off the ending to just get clone part
      $seq =~ s/\..*//;
      $warnings .= "ERROR 19(a): $gene_id ($Gene_info{$gene_id}{'Public_name'}) has no Positive_clone but info is available from '$tag' tag\n";
      print "." if ($verbose);
      # must use Inferred_automatically from Evidence hash for this type of info
      print ACE "\n\nGene : \"$gene_id\"\nPositive_clone \"$seq\" Inferred_automatically \"From sequence, transcript, pseudogene data\"\n" if ($ace);
    }
  }


  # Look for Genes with no Live tag but also no Merged_into or Killed tags
  if ( !defined $gene_id->at('Identity.Live') && !defined $gene_id->Merged_into ){
    print "." if ($verbose);
    my $tag = get_event($gene_id);
    if ( $tag ne "Killed" ){
      $warnings .= "ERROR 20(a): $gene_id ($Gene_info{$gene_id}{'Public_name'}) has no 'Live' tag, no 'Merged_into' and no 'Killed' tags => Go live\n";
      if ($ace){
	print ACE "\nGene : \"$gene_id\"\n";
	print ACE "Live\n";
      }
    }
  }


  # Look for genes with Live tag but also with Merged_into or Killed tags
  if ( defined $gene_id->at('Identity.Live') && ($gene_id->Merged_into || $gene_id->History(6)) ){
    print "." if ($verbose);
    my @merge =  $gene_id->Merged_into;
    if (@merge){
      $warnings .= "ERROR 20.1(a): $gene_id ($Gene_info{$gene_id}{'Public_name'}) has 'Live' tag but also has been merged into $merge[-1] ($Gene_info{$merge[-1]}{'Public_name'}) => Lose Live\n";
      if ($ace){
	print ACE "\nGene : \"$gene_id\"\n";
	print ACE "-D Live\n";
      }
    }
    
    if ( $gene_id->History ){
      my $tag = get_event($gene_id);
      if ($tag eq "Killed"){
	$warnings .= "ERROR 20.2(a): $gene_id ($Gene_info{$gene_id}{'Public_name'}) has 'Live' tag but also has 'Killed' tag => Lose Live\n";
	if ($ace){
	  print ACE "\nGene : \"$gene_id\"  \/\/20.2\n";
	  print ACE "-D Live\n";
	}
	print "." if ($verbose);
      }
    }
  }

  # checks that a Gene has both values for Map and Interpolated_map_positions or tags
  if ( defined $gene_id->Map(3) && $gene_id->Interpolated_map_position(2) ){
    $warnings .= "ERROR 21(a): $gene_id ($Gene_info{$gene_id}{'CGC_name'}) has both genetics and interpolated map positions\n";
    print "." if ($verbose);
    if ($ace){
      print ACE "\nGene : \"$Gene_info{$gene_id}{'Gene'}\"\n";
      print ACE "-D Interpolated_map_position\n";
    }
  }

  # checks that a Gene has identical CGC_name and Other_name
  if ( defined $gene_id->CGC_name && defined $gene_id->Other_name ){
    my @other_names =  $gene_id->Other_name;
    foreach my $o (@other_names) {
      if ( $o eq $gene_id->CGC_name ){
	$warnings .= "ERROR 22: $gene_id ($Gene_info{$gene_id}{'CGC_name'}) has an identical Other_name\n";
	print "." if ($verbose);
      }
    }
  }

  print LOG "$warnings" if(defined($warnings));
  return($non_CGC_to_seq, $non_CGC_non_seq);
}


sub get_event {
  my $gene_id = shift;

  # fetch the last event of history changes based on the info of Version_change
  # this look clumsy, but did not come up with a better solution yet,
  # (generating a string of a series of down-> based on the number of verison change is easy, but did not work)
  # 7 times hard coded version change should be enough to work find for a while, at least

  my @ver_ch = $gene_id->Version_change;

  my $tag = $gene_id->History->right->right->right->right->right if scalar @ver_ch == 1;
     $tag = $gene_id->History->right->down->right->right->right->right if scalar @ver_ch == 2;
     $tag = $gene_id->History->right->down->down->right->right->right->right if scalar @ver_ch == 3;
     $tag = $gene_id->History->right->down->down->down->right->right->right->right if scalar @ver_ch == 4;
     $tag = $gene_id->History->right->down->down->down->down->right->right->right->right if scalar @ver_ch == 5;
     $tag = $gene_id->History->right->down->down->down->down->down->right->right->right->right if scalar @ver_ch == 6;
     $tag = $gene_id->History->right->down->down->down->down->down->down->right->right->right->right if scalar @ver_ch == 7;

  return $tag;
}

# looks for seq. (predictted_gene, transcript) link to an allele, but which gene ids don't => make gene id -> allele connection
sub link_seq_to_Gene_based_on_allele {

  my $db = shift;
  my $query = "Find Allele * where (Predicted_gene|Transcript) & gene";

  push(my @alleles_link_to_Gene_and_seq, $db->find($query));
  foreach my $allele (@alleles_link_to_Gene_and_seq){
    my @Genes =(); my @cds =(); my @trans =();

    my (%Genes, %cds, %trans);
    @Genes = $allele -> Gene; foreach (@Genes){$Genes{$_}++}
    @cds   = $allele -> Predicted_gene;
    @trans = $allele -> Transcript;

    my %gene_ids;
    foreach my $e (@cds, @trans){
       $gene_ids{$Gene_info{$e}{'Gene'}}++;
    }
	
    foreach my $id (keys %gene_ids){
      if (!exists $Genes{$id}){
        print LOG "ERROR 23(a): $id ($Gene_info{$id}{'Public_name'}) is not linked to allele $allele\n";
        if ($ace){
          print ACE "\nAllele : \"$allele\"\n";
          print ACE "Gene \"$id\"\n";
        }
      }
    }
  }
}

# A seq. should normally be linked to only one gene id: there are cases where .a is WBGenex and .b is WBGy (eg, ZC416.8a/b)
# The query is to find sequences (CDS/Transcript/Pseudogene) that have more than one Sequence_name_for values
# this tells you if a gene id is linked to > 1 sequences
sub find_seqs_with_multiple_Gene_ids {
  my $db = shift;

  my @CDSs = $db->fetch(-query=>'Find Gene_name * where COUNT Sequence_name_for > 1');
  foreach my $cds (@CDSs){
    my @gid = $cds->Sequence_name_for;
    print LOG "ERROR 24: $cds is connected to multiple gene ids: @gid\n";
    print JAHLOG "ERROR 24: $cds is connected to multiple gene ids: @gid\n";
    $jah_errors++;
  }
}


                          #############################################################
                          #             SUBROUTINES FOR -c evidence option            #
                          #############################################################

sub check_evidence {

  my $WBPerson_F_M_L_names="Table-maker -p \"$def_dir/WBperson_first_middle_last_names.def\"\nquit\n";
  my @WBPerson = &process_WBPerson_names($WBPerson_F_M_L_names, $curr_db);

  print "\n\nChecking misuse of Evidence and converting Author to Person / Non-Person to Author:\n\n";
  print LOG "\n\nChecking misuse of Evidence and converting Author to Person / Non-Person to Author:\n";
  print LOG "-----------------------------------------------------------------------------------\n";


# dump flat files with time stamps
my $dump_dir = "/wormsrv1/geneace/CHECKS";

my $command=<<END;
Find Gene * 
show -a -T -f $dump_dir/gene_dump.ace

Find allele *
show -a -T -f $dump_dir/allele_dump.ace

Find strain *
show -a -T -f $dump_dir/strain_dump.ace

Find gene_class *
show -a -T -f $dump_dir/geneclass_dump.ace

Find 2_point_data *
show -a -T -f $dump_dir/2_pt_dump.ace

Find Multi_pt_data *
show -a -T -f $dump_dir/multi_pt_dump.ace

Find Pos_neg_data *
show -a -T -f $dump_dir/posneg_dump.ace

Find Laboratory *
show -a -T -f $dump_dir/lab_dump.ace

quit
END

  open (DUMP, "| $tace $default_db") || die "Failed to connect to Geneace";
  print DUMP $command;
  close DUMP;

  `cat $dump_dir/gene_dump.ace $dump_dir/allele_dump.ace $dump_dir/strain_dump.ace $dump_dir/2_pt_dump.ace $dump_dir/multi_pt_dump.ace $dump_dir/posneg_dump.ace $dump_dir/geneclass_dump.ace $dump_dir/lab_dump.ace > $dump_dir/class_dump.ace`;

  my @dumps = qw (gene_dump.ace allele_dump.ace strain_dump.ace geneclass_dump.ace 2_pt_dump.ace multi_pt_dump.ace posneg_dump.ace class_dump.ace lab_dump.ace);

  foreach (@dumps){system ("chmod 777 $dump_dir/$_")}

  open(IN, "$dump_dir/class_dump.ace") || die $!;

# look for person/author names that needs to be converted in 8 classes (regardless of which tag as the scripts greps from string pattern

  my $evid_errors = 0;
  my $updates = 0;
  my $info_num = 0;
  my (@counters, $class_obj, $class, $obj, $tag, $ori, $b4_evi, $name, $paper, $author, $last_name, $initials);

  while (<IN>){
    chomp;
    if ($_ =~ /^(Gene) : \"(.+)\" -O .+/){$class = $1; $obj = $2}
    if ($_ =~ /^(Allele) : \"(.+)\" -O .+/){$class = $1; $obj = $2}
    if ($_ =~ /^(Strain) : \"(.+)\" -O .+/){$class = $1; $obj = $2}
    if ($_ =~ /^(Gene_class) : \"(.+)\" -O .+/){$class = $1; $obj = $2}
    if ($_ =~ /^(2_point_data) : \"(.+)\" -O .+/){$class = $1; $obj = $2}
    if ($_ =~ /^(Multi_pt_data) : \"(.+)\" -O .+/){$class = $1; $obj = $2}
    if ($_ =~ /^(Pos_neg_data) : \"(.+)\" -O .+/){$class = $1; $obj = $2}
    if ($_ =~ /^(Laboratory) : \"(.+)\" -O .+/){$class = $1; $obj = $2}

    if ($_ =~ /((\w+)\s+.+)Person_evidence -O .+\"(.+)\" -O.+/){
      $ori = $_;
      $b4_evi = $1;	
      $tag = $2;
      $name = $3;
      if ($name !~ /WBPerson\d+/){
	#$evid_errors++;
	print LOG "\nERROR: $class $obj has non-Person $name under main tag $tag\n";

	@counters = get_WBPerson_ID($name, $class, $obj, $tag, $ori, $b4_evi, "PtoA");
	$evid_errors += $counters[0];
	$updates += $counters[1];
	$info_num += $counters[2];
      }
    }
    if ($_ =~ /((\w+)\s+.+)Paper_evidence -O .+\"(.+)\" -O.+/){
      $ori = $_;
      $b4_evi = $1;
      $tag = $2;
      $paper = $3;
      $class_obj = $class." : "."\"$obj\"";
      if ($paper !~ /\[.+\]/){
        $evid_errors++;
	print LOG "\nERROR: $class $obj has Paper $paper under main tag $tag\n";
	if ($ace){
	  print ACE "\n$class_obj\n";
	  print ACE "-D $ori\n\n";
	  print ACE "\n$class_obj\n";
	  $paper =~ s/\[|\]//g;
	  print ACE "$b4_evi Paper_evidence \"\[$paper$\]\"\n";
        }
      }
     # Likely to be deleted, when Caltech is clear about rules of using cgc and pmid
     # if ($paper !~ /\[cgc\d+\]/ && $paper =~ /\[pmid(\d+)\]/){
#	$evid_errors++;
#	$paper = $1;
#	print LOG "\n: $class $obj has Paper $paper under main tag $tag\n";
#	if ($ace){
#	  print ACE "\n$class_obj\n";
#	  print ACE "-D $ori\n\n";
#	  print ACE "\n$class_obj\n";
#	  print ACE "$b4_evi PMID_evidence \"\[$paper$\]\"\n"; 
#        }
#      }
    }

    if ($_ =~ /((\w+)\s+.+)Author_evidence -O .+\"(.+)\" -O.+/){
      $ori = $_;
      $b4_evi = $1;
      $tag = $2;
      $author = $3;

      @counters = get_WBPerson_ID($author, $class, $obj, $tag, $ori, $b4_evi);
      $evid_errors += $counters[0];
      $updates += $counters[1];
      $info_num += $counters[2];
    }
    if ($_ =~ /(Unregistered_lab_members)\s+-O\s\"\d+.+_\w+\" \"(.+)\" -O .+/){

      $ori = $_;
      $tag = $1;
      $author = $2;
      #print $author, "#\n";
      # print "$author, $class, $obj, $tag, $ori@\n";
      @counters = get_WBPerson_ID($author, $class, $obj, $tag, $ori);
      $evid_errors += $counters[0];
      $updates += $counters[1];
      $info_num += $counters[2];
    }

  }
  print LOG "\n\nThere are $evid_errors Evidence errors in 8 classes checked\n";
  print LOG "\n$updates Authors can be converted to Persons\n";
  print LOG "\n$info_num Authors are not Persons\n" if $verbose;
  system ("rm -f $dump_dir/*_dump.ace");

 #########################################################################
  # functions called by check_evidence() to do Author to Person convertion
  #########################################################################

  # make hashes for last name and its corresponding first/middle name and WBPersonID
  # these hashes are used by get_WBPerson_ID subroutine

  sub process_WBPerson_names {
    my ($def, $db)=@_;
    my ($WBPerson, $F_name, $M_name, $L_name, $F_char, $M_char);
    open (FH, "echo '$def' | $tace $db | ") || die "Couldn't access current_DB\n";
    while (<FH>){
      chomp($_);
      if ($_ =~ /^\"(WBPerson\d+)\"\s+\"(\w+)\"\s+\"(\w+|\w+.)\"\s+\"(\w+|\w+-\w+)\"$/){
	$WBPerson = $1;
	$F_name = $2;
	$M_name = $3;
	$L_name = $4;
	$F_char = substr ($F_name, 0, 1);
	$M_char = substr ($M_name, 0, 1);
	push (@{$L_name_F_M_WBP{$L_name}}, $F_char.$M_char, $F_char, $WBPerson);
      }
      if ($_ =~ /^\"(WBPerson\d+)\"\s+\"(\w+)\"\s+\"(\w+|\w+-\w+)\"$/){
	$WBPerson = $1;
	$F_name = $2;
	$L_name = $3;
	$F_char = substr ($F_name, 0, 1);
	push (@{$L_name_F_WBP{$L_name}}, $F_char, $WBPerson);
      }
    }
    close FH;
  }

  # last name (key) is checked against hashes created from process_WBPerson_names subroutine
  # the values of the key (first name, middle name) are checked to assign identify

  # convert authors that have WBPersonID to person 
  # (or unregistered_lab_members to registered_lab_members for laboratory class)

  # move names in person_evidence that are not person to author_evidence

  sub get_WBPerson_ID {
    my ($name, $class, $obj, $tag, $ori, $b4_evi, $conversion) = @_;
    my ($last_name, $initials, $num);
    my $class_obj = $class." : "."\"$obj\"";
    my $convert = 0;
    my $info_count = 0;
    my $evid_errors = 0;

    if ($name =~ /\w+\,\w+/ || $name =~ /\w+\,\s+\w+/){
      $evid_errors++;
      if (!defined $conversion){
	($last_name, $initials) = split(/ /, $name);
	$last_name =~ s/,//;
	print LOG "\nERROR(a): $class $obj has $name (Author) under main tag $tag\n";
	print LOG"=====>Correct $name as $last_name $initials\n";
	if ($ace){
	  print ACE "\n$class_obj\n";
	  print ACE "-D $ori\n\n";
	  print ACE "\n$class_obj\n";
	  if (defined $b4_evi){
	    print ACE "$b4_evi Author_evidence \"$last_name $initials\"\n";
	  }
	  else {
	    print ACE "$tag \"$last_name $initials\"\n";
	  }
	}
      }
    }
    else {
      ($last_name, $initials) = split(/ /, $name);
    }

    if (!exists $L_name_F_WBP{$last_name} && !exists $L_name_F_M_WBP{$last_name}){
      if (defined $conversion){
	print LOG "=====>Move $name under Author_evidence as NO corresponding WBPersonID exists\n";
      }
      if ($verbose && !defined $conversion){
	$info_count++; 
	print LOG "\nINFO: $class $obj has $name (Author under $tag tag): NOT yet a Person\n";
      }
      if ($ace && defined $conversion){
	print ACE "\n$class_obj\n";
	print ACE "-D $ori\n\n";
	print ACE "\n$class_obj\n";
	if (defined $b4_evi){
	  print ACE "$b4_evi Author_evidence \"$last_name $initials\"\n";
	}
      }
    }

    if (exists $L_name_F_WBP{$last_name}){
      $num = scalar @{$L_name_F_WBP{$last_name}};

      for (my $i=0; $i< $num; $i=$i+2){
	if ($initials eq ${@{$L_name_F_WBP{$last_name}}}[$i]){
	  $convert++;
	  if (!defined $conversion){
	    print LOG "\nUPDT(a): $class $obj has $name (Author) under $tag tag\n";
          }
	  if ($num == 2){
	    print LOG "=====>$name can now be Person ${@{$L_name_F_WBP{$last_name}}}[$i+1]\n";
	    if ($ace){
              print ACE "\n$class_obj\n";
              print ACE "-D $ori\n\n";
	      print ACE "\n$class_obj\n";
	      if (defined $b4_evi){
		print ACE "$b4_evi"." Person_evidence \"${@{$L_name_F_WBP{$last_name}}}[$i+1]\"\n";
	      }
	      else {
		print ACE "Registered_lab_members \"${@{$L_name_F_WBP{$last_name}}}[$i+1]\"\n";
	      }	
            }
	  }
	  else {
	    print LOG "=====>$name might be Person ${@{$L_name_F_WBP{$last_name}}}[$i+1]\n";
	    if ($ace){
              print ACE "\n$class_obj\n";
              print ACE "-D $ori\n\n";
	      print ACE "\n$class_obj\n";
	      if (defined $b4_evi){
		print ACE "$b4_evi"." Person_evidence \"${@{$L_name_F_WBP{$last_name}}}[$i+1]\"\n";
	      }
	      else {
		print ACE "Registered_lab_members \"${@{$L_name_F_WBP{$last_name}}}[$i+1]\"\n";
	      }	
            }
	  }
	}
      }
    }

    if (exists $L_name_F_M_WBP{$last_name}){
      $num = scalar @{$L_name_F_M_WBP{$last_name}};

      for (my $i=0; $i< $num; $i=$i+3){
	if ($initials eq ${@{$L_name_F_M_WBP{$last_name}}}[$i] ||
            $initials eq ${@{$L_name_F_M_WBP{$last_name}}}[$i+1] ){
          $convert++;
          if (!defined $conversion){
	    print LOG "\nUPDT(a): $class $obj has $name (Author) under $tag tag\n";
          }
       	  if ($num == 3){
	    print LOG "=====>$name can now be Person ${@{$L_name_F_M_WBP{$last_name}}}[$i+2]\n";
            if ($ace){
              print ACE "\n$class_obj\n";
              print ACE "-D $ori\n\n";
	      print ACE "\n$class_obj\n";
	      if (defined $b4_evi){
		print ACE "$b4_evi"." Person_evidence \"${@{$L_name_F_M_WBP{$last_name}}}[$i+2]\"\n";
	      }
	      else {
		print ACE "Registered_lab_members \"${@{$L_name_F_M_WBP{$last_name}}}[$i+2]\"\n";
	      }
            }
	  }
	  else {
	    print LOG "=====>$name might be Person ${@{$L_name_F_M_WBP{$last_name}}}[$i+2]\n";
            if ($ace){
              print ACE "\n$class_obj\n";
              print ACE "-D $ori\n\n";
	      print ACE "\n$class_obj\n";
	      if (defined $b4_evi){
		print ACE "$b4_evi"." Person_evidence \"${@{$L_name_F_M_WBP{$last_name}}}[$i+2]\"\n";
	      }
	      else {
		print ACE "Registered_lab_members \"${@{$L_name_F_M_WBP{$last_name}}}[$i+2]\"\n";
	      }
            }
	  }
	}
      }
    }
    $conversion =();
    return $evid_errors, $convert, $info_count;
  }
}	

                          ###############################################################
                          #             SUBROUTINES FOR -c laboratory option            #
                          ###############################################################


sub process_laboratory_class{

  print "\n\nChecking Laboratory class for errors:\n";
  print LOG "\n\nChecking Laboratory class for errors:\n";
  print LOG "-------------------------------------\n";

  my @labs = $db->fetch(-class => 'Laboratory',
		        -name  => '*');

  # test for Allele_designation and Representative tags
  foreach my $lab (@labs){
    if ( $verbose && (!defined $lab -> Allele_designation) && $lab =~ /[A-Z]{3,3}/ ){
      print LOG "INFO: $lab has no Allele_designation (exception)\n";
    }
    if ( (!defined $lab -> Allele_designation) && $lab !~ /[A-Z]{3,3}/ ){
      print LOG "ERROR: $lab has no Allele_designation\n";
    }
    if( (!defined $lab->Representative) && $lab !~ /XA|CGC/ ){
      print LOG "ERROR: $lab has no Representative\n";
    }
    if( defined $lab->at('Laboratory.CGC.Representative') && !defined $lab->Representative ){
      print LOG "ERROR: $lab has Representative tag without value\n";
    }
    if ( defined $lab->Representative && $lab -> Representative !~ /^WBPerson\d+/ ){
      print LOG "$lab representative (", $lab->Representative, ") is not using WBPerson# format\n";
    }
  }
}


                          ###########################################################
                          #             SUBROUTINES FOR -c allele option            #
                          ###########################################################


sub process_allele_class{

  print"\n\nChecking Allele class for errors:\n";
  print LOG "\n\nChecking Allele class for errors:\n";
  print LOG "---------------------------------\n";

  # when an allele is linked to a predicted_gene and not a gene, is that predicted_gene already linked to a gene_id?
  # if yes, make allele - Gene id connection

  foreach my $tag ("Predicted_gene", "Transcript"){
    my $query_1 = "Find allele * where $tag & !Gene; > $tag; Gene"; # alleles have no gene but have predicted_gene/transcript which are linked to Gene
    my $query_2 = "Find allele * where $tag & !Gene";               # alleles have no Gene

    my (@seqs_linked_to_allele_and_gene, %seqs_linked_to_allele_and_gene,
        @alleles_linked_to_seqs_and_not_gene, %alleles_linked_to_seqs_and_not_gene);

    push( @seqs_linked_to_allele_and_gene, $db->find($query_1) );
    push( @alleles_linked_to_seqs_and_not_gene, $db->find($query_2) );

    # hash set for quick lookup
    foreach (@seqs_linked_to_allele_and_gene){$seqs_linked_to_allele_and_gene{$_}++};
    foreach (@alleles_linked_to_seqs_and_not_gene){$alleles_linked_to_seqs_and_not_gene{$_}++};

    foreach my $seq (@seqs_linked_to_allele_and_gene){
      my %SEQ =(); $SEQ{$seq}=$seq; # convert ace obj to simple string
      my @alleles = $seq -> Alleles;
      foreach my $e (@alleles){
	if ( exists $alleles_linked_to_seqs_and_not_gene{$e} ){

	  # a seq. maybe linked to > 1 gene ids
	  my @gene_ids = $ga -> get_unique_from_array( @{$seqs_to_gene_id{$SEQ{$seq}}} );
	  foreach (@gene_ids){

	    # check this gene id has also a CGC_name / Sequence_name
	    foreach my $tag ("CDS", "Transcript"){
	      if ( $Gene_info{$_}{$tag}){
		if ( $Gene_info{$_}{'CGC_name'} ){
		  print LOG "ERROR(a): $e should be linked to $_ ($Gene_info{$_}{'CGC_name'}) based on $seq of $e\n";
		}
		elsif ( $Gene_info{$_}{'Sequence_name'} ){
		  print LOG "ERROR(a): $e should be linked to $_ ($Gene_info{$_}{'Sequence_name'}) based on $seq of $e\n";
		}
		if ($ace){
		  print ACE "\nAllele : \"$e\"\n";
		  print ACE "Gene \"$_\"\n";
		}
	      }
	    }
	  }
	}
      }
    }
  }

  my @alleles = $db->fetch(-class => 'Allele',
                 	   -name  => '*');

  my (%allele_desig_to_LAB, $allele, $desig, $desig2);

  my %overlapped_clones = $ga->get_overlapped_clones();

  %allele_desig_to_LAB = $ga -> allele_desig_to_lab($default_db);

  foreach my $allele (@alleles){

    # check allele has no location tag
    if( !defined $allele->Location ){

      # catch non-standard upper-case allele name
      if ($allele =~ /^[A-Z]+/){
	print LOG "ERROR: $allele has no Location (no info available)\n";
      }
      else {
	print LOG "ERROR : $allele has no Location info\n";

	# acefile output for normal or double alleleles having no location tag
	if ($ace){
	  if ($allele =~ /^([a-z]{1,})\d+$/){
	    $desig = $1;
	    &lab_assignment(\%allele_desig_to_LAB, $allele, $desig);
	    next;
	  }

	  ######################
	  # catch double alleles
          ######################

	  if ($allele =~ /^([a-z]{1,})\d+([a-z]{1,})\d+$/){

	    # double allele has same designation (eg, pk100pk123)
	    $desig = $1; $desig2 = $2;
	    &lab_assignment(\%allele_desig_to_LAB, $allele, $desig) if ("$desig" eq "$desig2");

	    # double allele has diff designation
	    if ("$desig" ne "$desig2"){
	      &lab_assignment(\%allele_desig_to_LAB, $allele, $desig);
	      &lab_assignment(\%allele_desig_to_LAB, $allele, $desig2);
	    }
	    next;
	  }
	}
      }
    }

    # check that LAB desig to allele desig is correct
    if ( defined $allele->Location ) {
      my $lab = $allele->Location;
      if ($allele =~ /^([a-z]{1,})\d+$/){
	$desig = $1;
	if ( $allele_desig_to_LAB{$desig} ne $lab ){
	  print LOG "ERROR(a): $allele ($allele_desig_to_LAB{$desig}) is linked to wrong lab ($lab)\n";
	  &lab_assignment(\%allele_desig_to_LAB, $allele, $desig, "correction") if $ace;
	}
      }
    }

    sub lab_assignment {
      my ($allele_desig_to_LAB, $allele, $desig, $option) = @_;
      my %allele_desig_to_LAB = %$allele_desig_to_LAB;

      print ACE "\nAllele : \"$allele\"\n" if $option;
      print ACE "-D Location\n"            if $option;
      print ACE "\nAllele : \"$allele\"\n";
      print ACE "Location \"$allele_desig_to_LAB{$desig}\"\n";
    }

    if($allele -> Gene){
      my @geneids=$allele->Gene;

      if (scalar @geneids > 1){
	print LOG "CHECK: $allele is connected to more than one gene ids: @geneids\n";
      }
    }

    # test allele has no method and/or method matches tags about an allele, eg, Deletion tag -> Deletion_allele
    my $method =(); my $method_is =();
    if    ( defined $allele -> Allele_type &&  $allele -> Allele_type eq "Insertion" && !defined $allele -> Transposon_insertion ){$method = "Insertion_allele"}
    if    ( defined $allele -> Allele_type &&  $allele -> Allele_type eq "Transposon_insertion" )    {$method = "Transposon_insertion"}
    elsif ( defined $allele -> Allele_type &&  $allele -> Allele_type eq "Deletion" )                {$method = "Deletion_allele"}
    elsif ( defined $allele -> Allele_type &&  $allele -> Allele_type eq "Deletion_with_insertion" ) {$method = "Deletion_and_insertion_allele"}
    elsif ( defined $allele -> Allele_type &&  $allele -> Allele_type eq "Substitution" )            {$method = "Substitution_allele"}

    $method_is = $allele -> Method if defined $allele -> Method;

    if (!$method_is){
      print  LOG "ERROR(a): Allele $allele has no Method '$method'\n" if $method;
      print  LOG "ERROR(a): Allele $allele has no Method 'Allele'\n" if !$method;
      if ($ace){
        print ACE "\nAllele : \"$allele\"\n";
        print ACE "Method \"$method\"\n" if $method;
        print ACE "Method \"Allele\"\n" if !$method;
      }
    }
    else {
      if (defined $method && $method ne $method_is){
        print LOG "ERROR(a): $allele has wrong method ($method_is): change to $method\n";
        if ($ace){
          print ACE "\nAllele : \"$allele\"\n";
          print ACE "-D Method\n";
          print ACE "\nAllele : \"$allele\"\n";
          print ACE "Method \"$method\"\n";
        }
      }
    }

    # find alleles that have flanking_seqs but no SMAPPED sequence
    if ( $allele -> Flanking_sequences && ! defined $allele -> Sequence ){
      print LOG "ERROR: Allele $allele has flanking sequences but has no parent sequence\n";
    }

    foreach my $tag ("Predicted_gene", "Transcript"){

      # find alleles linked to predicted_gene/transcript but no SMAPPED sequence 
      if ( $allele -> $tag && ! defined $allele -> Sequence ){
	my @genes = $allele -> $tag;
	my $seq = $allele -> Sequence;

	print LOG "ERROR(a): Allele $allele has $tag (@genes) but has no parent sequence\n";
	if ($ace){
	  if ( $genes[0] =~ /(.+)\..+/ ) { # only take first seq. if multiple
	    my $parent =  $1;
	    print ACE "\n\nAllele : \"$allele\"\n";
	    print ACE "Sequence \"$parent\"\n";
	  }
	}
      }

      # find alleles which have unmatched parent sequence and seq. obj. names
      if ( $allele -> $tag && $allele -> Sequence ){

	my @genes = $allele -> $tag;
	my $seq = $allele -> Sequence;
 	my %overlaps;
	
	if ($seq !~ /SUPERLINK.+/){
	  if ( $genes[0] =~ /(.+)\..+/ ){ # only take first seq. if multiple
	    my $parent =  $1;
	    if ( $parent ne $seq && exists $overlapped_clones{$seq} ){
	      foreach my $e (@{$overlapped_clones{$seq}}){$overlaps{$e}++}
	      if ( exists $overlaps{$seq} ){
		print LOG "INFO: $allele has a different parent sequence ($seq) based on its sequence name(s) (@genes)(overlapped clones?)\n";
	      }
	    }
	    if ( $parent ne $seq && !exists $overlapped_clones{$seq} ){
	      print LOG  "ERROR(a): $allele has a different parent sequence ($seq) based on its sequence name(s) (@genes)\n";
	      if ($ace){
		print ACE "\n\nAllele : \"$allele\"\n";
		print ACE "Sequence \"$parent\"\n";
	      }
	    }
	  }
	}
      }
    }
  }
}


                          ###########################################################
                          #             SUBROUTINES FOR -c strain option            #
                          ###########################################################


sub process_strain_class {

  # Check if sequence name of a strain genotype is now connected to a CGC_name
  print"\n\nChecking Strain class for errors:\n";
  print LOG "\n\nChecking Strain class for errors:\n";
  print LOG "---------------------------------\n";

  my @strains = $db->fetch('Strain','*');
  foreach my $strain (@strains){
    if (!$strain->Location){
      print LOG "WARNING(a): Strain $strain has no location tag\n";
      if ($ace){
	$strain =~ /([A-Z]+)\d+/;
	print ACE "\n\nStrain : \"$strain\"\n";
	print ACE "Location \"$1\"\n";
      }
    }
    else {
      my $cgc=$strain->Location;
      if ($strain->Genotype){
	my $genotype = $strain->Genotype;
	my $extract = $genotype;
	   $extract =~ s/\(|\)|\/|\+|;|\?|\{|\}|,|\=|\.$/ /g;
	   $extract =~ s/ I | II | III | IV | V | X / /g;
	   $extract =~ s/ I | II | III | IV | V | X | f / /g; # further tidying up of chromosomes
	   $extract =~ s/^\s|\w{3}-\s| f | A //g;
	   $extract =~ s/\s{1,}/ /g;
	my @items=split(/ /,$extract);

	foreach (@items){
	  if( exists $seqs_to_gene_id{$_} ){
	    my @gene_ids= @{$seqs_to_gene_id{$_}};
	    @gene_ids = $ga->get_unique_from_array(@gene_ids); 
	    if ($cgc eq "CGC"){
	      foreach my $e (@gene_ids){
		print LOG "WARNING: CGC Strain $strain has sequence_name $_ in Genotype, which can now become $Gene_info{$e}{'CGC_name'}\n" if $Gene_info{$e}{'CGC_name'};
	      }
	    }
	    else {
	      foreach my $e (@gene_ids){
		print LOG "WARNING: Non_CGC Strain $strain has sequence_name $_ in Genotype, which can now become $Gene_info{$e}{'CGC_name'}\n" if $Gene_info{$e}{'CGC_name'};
	      }
	    }
	  }
	}
      }
    }
  }

  my ($locus, %allele_locus, %strain_genotype, $cds, %locus_cds, $main, $allele);

  my $get_genotype_in_strain="Table-maker -p \"$def_dir/strain_genotype.def\"\nquit\n";
  my $allele_to_locus="Table-maker -p \"$def_dir/allele_to_locus.def\"\nquit\n";

  open (FH1, "echo '$get_genotype_in_strain' | $tace $default_db | ") || die $!;
  open (FH2, "echo '$allele_to_locus' | $tace $default_db | ") || die $!;

  while(<FH1>){
    chomp;
     if ($_ =~ /\"(.+)\"\s+\"(.+)\"/){
      $strain_genotype{$1} = $2;
    }
  }
  close FH1;

  while (<FH2>){
    chomp $_;
    if ($_ =~ /\"(.+)\"\s+\"(.+)\"/){
      my $gene_id = $2;
      $gene_id =~ s/\\//;
      push(@{$allele_locus{$1}}, $Gene_info{$gene_id}{'CGC_name'}) if exists $Gene_info{$gene_id}{'CGC_name'};
    }
  }
  close FH2;

  foreach my $strain (keys %strain_genotype){
    my @matches = ($strain_genotype{$strain} =~  /((Cb-\w{3,3}-\d+|Cr-\w{3,3}-\d+|\w{3,3}-\d+)\(\w+\d+\))/g);
    foreach (@matches){
      my @la = split(/\s+/, $_);
      foreach (@la){
	if ($_ =~ /(Cb-\w{3,3}-\d+|Cr-\w{3,3}-\d+|\w{3,3}-\d+)\((\w+\d+)\)/){
	  $locus = $1; $allele = $2; 
	  # diff allele->locus link in geneace and allele->locus in strain genotype
	  # if diff, print error LOG
	
	  if ( defined @{$allele_locus{$allele}} ){
	    my @LOci = @{$allele_locus{$allele}};
	    my %LOci;
	    foreach (@LOci){$LOci{$_}++};
	    if (!exists $LOci{$locus} ){
	      print LOG "ERROR: Strain $strain has $locus($allele) in genotype: ";
	      print LOG "change each $locus to @{$allele_locus{$allele}}\n";
	    }
	  }
	}
      }
    }
  }
}

                          ##################################################################
                          #             SUBROUTINES FOR -c rearrangement option            #
                          ##################################################################


sub process_rearrangement {

  print"\n\nChecking Rearrangement class for errors:\n";
  print LOG "\n\nChecking Rearrangement class for errors:\n";
  print LOG "----------------------------------------\n";
  # checks presence of non-rearrangement object 
  # as objects of Rearrangement class

  my @rearr;
  my $count = 0;
  @rearr = $db -> fetch('Rearrangement','*');
  foreach (@rearr){
    if ($_ !~/\w+(Df|Dp|Ex|T|In|C|D)\d*/){
      $count++;
      print LOG "WARNING: $_ is NOT an object of Rearrangement\n";
    }
  }
  print LOG "No errors found\n" if $count == 0;
}

                          ###########################################################
                          #             SUBROUTINES FOR -c xref option              #
                          ###########################################################


sub check_bogus_XREF {

  # Does two things:
  #  A: finding deleted parent CDS name after isoforms are created
  #  B: finding bogus XREF from CDS names that are typos

  print "\nChecking bogus XREF debris of deleted CDS / Transcript / Pseudogene / Gene_name from Gene obj. . . .\n";
  print LOG "\nChecking bogus XREF debris of deleted CDS / Transcript / Pseudogene / Gene_name from Gene obj. . . .\n";
  print LOG "-----------------------------------------------------------------------------------------------------\n";

  my $query_cds        = "Find CDS * where !(yk*) & *.*; Gene";
  my $query_transcript = "Find Transcript * ; Gene";
  my $query_pseudo     = "Find Pseudogene * ; Gene";
  my $query_gname      = "Find Gene_name *.*"; 
  my $query_gene      = "Find Gene * where (CDS|transcript|pseudogene)";

  push(my @CDS,   $db->find($query_cds));
  push(my @TRANS, $db->find($query_transcript));
  push(my @PSEUDO,$db->find($query_pseudo));
  push(my @GNAME, $db->find($query_gname));
  push(my @gene_ids,  $db->find($query_gene));

  my $error = 0;

  # A: finding phantom deleted seq name after isoforms are created for a Gene id
  $error = find_bogus(\@CDS, "CDS");
  $error = find_bogus(\@TRANS, "Transcripts");
  $error = find_bogus(\@PSEUDO, "Pseudogene");
  $error = find_bogus(\@GNAME, "Gene_name");

  # B: finding bogus XREF from CDS/Transcrpt/Pseudogene tag of a Gene id to Gene tag of a Sequence obj.
  my (%gene_id_seq_A, %gene_id_seq_B); # hash A, gene_id linked to seq. in seq objs, hash B, gene_id linked to seq. in gene obj.

  my @all = (\@CDS, \@TRANS, \@PSEUDO);
  foreach my $e (@all){
    foreach (@{$e}){
      if(defined $_ -> Gene ) {push(@{$gene_id_seq_A{$_ -> Gene}}, $_)} # key is gene_id, value is seq. name
    }
  }

  foreach (@gene_ids){
    if( defined $_ -> CDS ){push(@{$gene_id_seq_B{$_}}, $_ -> CDS) }    # key is gene_id, value is seq. name
    if( defined $_ -> Transcript ){push (@{$gene_id_seq_B{$_}}, $_ -> Transcript) }
    if( defined $_ -> Pseudogene ){push (@{$gene_id_seq_B{$_}}, $_ -> Pseudogene) }
  }

  foreach (keys %gene_id_seq_A){ 
    if (exists $gene_id_seq_B{$_}){

      # compare seq. obj. in a Gene class with seq. obj linked to same Gene in seq. classes
      # extra obj means bogus obj

      my @diff = $ga->array_comp(\@{$gene_id_seq_A{$_}},  \@{$gene_id_seq_B{$_}}, "diff");
      if (scalar @diff > 1){
	print LOG "ERROR: Found bogus @diff linked to $Gene_info{$_}{'Public_name'}: check ?Gene or ?CDS/?Transcript/?Pseudo\n";
	$error = 1;
      }
    }
  }

  print LOG "No bogus XREF link found\n" if $error == 0;

  #################################################################################################
  # HOW this routine works: 
  # split a sequence eg. Y110A7A.10a, into "Y110A7A.10" (left: as key) and "a" (right: as value)
  # if a sequence has no right part (ie, not an isoform), then "NA" is assigned.
  # and if a key's value has "NA", other than a/b/c/d..etc, then the one without isoform is invalid
  #
  # This routine checks only deleted bogus parent seq. names when isoforms are created
  # it cannot check bogus seq. names created by typos
  ##################################################################################################

  sub find_bogus {
    my ($class, $cat) = @_;
    my %Seqs;
    my @class = @{$class};

    foreach (@class){
      my ($left, $right); # eg, for B0034.1a, left is "B0034.1" and right is "a"

      if ($_ =~ /^(.+\.\d+)(\D)$/){$left = $1; $right = $2}
      if ($_ =~ /^(.+\.\d+)$/){$left = $1; $right = "NA"}
      push(@{$Seqs{$left}}, $right) if defined $left;
      $left =();
    }

    my $error=0;

    foreach (keys %Seqs){
      my $counter_NA = 0; my $counter_iso = 0;
      foreach my $e (@{$Seqs{$_}}){
	if ($e eq "NA"){	# ie, has somthing like XX.1 , XX.1a and XX.1b
	  $counter_NA++;
	}
	else {
	  $counter_iso++;
	}
      }
      if ($counter_iso != 0 && $counter_NA != 0){
	print LOG "ERROR: Found bogus $_ in $cat class\n";
	$error = 1;
      }
    }
    return $error;
  }
}
                          ############################################################
                          #             SUBROUTINES FOR -c mapping option            #
                          ############################################################


sub check_genetics_coords_mapping {

  print "\nChecking discrepancies in genetics/coords mapping:\n";
  print LOG "\nChecking discrepancies in genetics/coords mapping:\n";
  print LOG "--------------------------------------------------\n";
  print JAHLOG "\nChecking discrepancies in genetics/coords mapping:\n";
  print JAHLOG "--------------------------------------------------\n";
  system ("/wormsrv2/scripts/get_interpolated_gmap.pl -db /wormsrv1/geneace -diff");
  my $map_diff = "/wormsrv2/logs/mapping_diff.".$rundate;
  open(IN, $map_diff) || die $!;
  while(<IN>){
    print LOG $_;
    print JAHLOG $_;
  }
}

                          #######################################################
                          #             SUBROUTINES FOR -c ps option            #
                          #######################################################

sub int_map_to_map_loci {

  # Look for Gene(loci) without map and mapping_data but have allele and seq. connection and interpolated_map_position
  # This is for creating inferred multip_pt obj for such loci found 
  # sent to JAH for approval

  my $error=0;
  my $header = "\n\nChecking Genes without map & mapping_data but have allele & seq. connection & interpolated_map_position\n";
  my $sep = "--------------------------------------------------------------------------------------------------------\n";
  print $header;
  print LOG $header, $sep;
  print JAHLOG $header, $sep;

  my $int_loci  = "find Gene * where !mapping_data & allele & (CDS|transcript|pseudogene) & interpolated_map_position & species =\"*elegans\"";
  my %INT_loci;

  # need to increment again because this is run before autoace_minder -initial is run so build hasn't actually started
  my $version = $next_build_ver +1;
  open(INT_map_TO_MAP, ">/wormsrv1/geneace/JAH_DATA/MULTI_PT_INFERRED/loci_become_genetic_marker_for_WS$version") || die $!;

  # create a list of "promoted" loci
  push( my @int_loci, $db->find($int_loci) );
  my %Alleles = $ga->get_non_Transposon_alleles($db); # all Geneace alleles which have no Transposon_insertion tag

  foreach (@int_loci){
    my @alleles = $_ -> Allele(1);
    foreach my $e (@alleles){
      if (exists $Alleles{$e} ){

	my $int_map = $_ -> Interpolated_map_position(1);
	my $int_pos = $_ -> Interpolated_map_position(2);
	if (exists $Gene_info{$_}{'CGC_name'}){
	  $error++;
	  print LOG "$Gene_info{$_}{'CGC_name'} ($_ => $e) has interpolated_map which can be updated to Map: $int_pos\n";
	  print JAHLOG "$Gene_info{$_}{'CGC_name'} ($_ => $e) has interpolated_map which can be updated to Map: $int_pos\n";
	
	  # keep a copy here
	  print INT_map_TO_MAP "\nGene : \"$_\" \/\/ $Gene_info{$_}{'CGC_name'}\n";
	  print INT_map_TO_MAP "-D Interpolated_map_position \n";
	  print INT_map_TO_MAP "\nGene : \"$_\"\n";
	  print INT_map_TO_MAP "Map \"$int_map\" Position $int_pos\n";
	  print INT_map_TO_MAP "Remark \"Map position created from combination of previous interpolated map position (based on known location of sequence) and allele information.  Therefore this is not a genetic map position based on recombination frequencies or genetic experiments.  This was done on advice of the CGC.\" CGC_data_submission\n";
	  last;
	}
      }
    }
  }

  print LOG    "Total: $error to become inferred genetic marker(s)\n\n";
  print JAHLOG "Total: $error to become inferred genetic marker(s)\n\n";
}



                          ############################################################
                          #             SUBROUTINES FOR -c multipt option            #
                          ############################################################


sub check_dubious_multipt_gene_connections {

  my $header = "\n\nChecking dubious multi-pt <-> Gene association\n";
  my $sep = "-----------------------------------------------------------------------------------\n";
  print $header;
  print LOG $header, $sep;

  system("perl5.8.0 /wormsrv2/scripts/GENEACE/check_dubious_multi_pt_2_locus.pl");
  print LOG `cat /wormsrv2/logs/dubious_multiPt_2_locus.$rundate`;
  print JAHLOG `cat /wormsrv2/logs/dubious_multiPt_2_locus.$rundate`;
  print ACE `cat /wormsrv1/geneace/CHECKS/multiPt_2_locus.ace` if $ace;
  `rm -f /wormsrv1/geneace/CHECKS/multiPt_2_locus.ace`;
}

sub usage {
  my $error = shift;
  if ($error eq "Help") {
    # Normal help menu
    system ('perldoc',$0);
    exit (0);
  }
}

sub create_log_files{

  # Create history logfile for script activity analysis
  $0 =~ m/\/*([^\/]+)$/; system ("touch /wormsrv2/logs/history/$1.`date +%y%m%d`")if $machine;

  # create main log file using script name for
  my $script_name = $1;
  $script_name =~ s/\.pl//; # don't really need to keep perl extension in log name

  $log = "/wormsrv2/logs/$script_name.$rundate.$$" if $machine;
  $log = "/nfs/disk100/wormpub/tmp/$script_name.$rundate" if !$machine;

  open (LOG, ">$log") or die "cant open $log";
  print LOG "$script_name\n";
  print LOG "started at ",`date`,"\n";
  print LOG "=============================================\n";
  print LOG "\n";
  print LOG "The (a) following ERROR, or UPDT, eg, indicates ace output \n$acefile for direct upload to correct problems.\n\n";

  $jah_log = "/wormsrv2/logs/$script_name.jahlog.$rundate.$$" if $machine;
  $jah_log = "/nfs/disk100/wormpub/tmp/$script_name.jahlog.$rundate" if !$machine;

  open(JAHLOG, ">>$jah_log") || die "Can't open $jah_log\n";
  print JAHLOG "This mail is generated automatically for CGC on $rundate\n"; 
  print JAHLOG "If you have any queries please email krb\@sanger.ac.uk\n\n";
  print JAHLOG "=========================================================================\n";

  # create separate log with errors for Erich
  $caltech_log = "/wormsrv2/logs/geneace_check.caltech_log.$rundate.$$" if $machine;
  $caltech_log = "/nfs/disk100/wormpub/tmp/$script_name.caltech_log.$rundate" if !$machine;

  open(CALTECHLOG,">$caltech_log") || die "cant open $caltech_log";
  print CALTECHLOG "$0 started at ",`date`,"\n";
  print CALTECHLOG "This mail is generated automatically for Caltech\n";
  print CALTECHLOG "If you have any queries please email krb\@sanger.ac.uk\n\n";
  print CALTECHLOG "================================================================================================\n";

  `chmod 777 $log $jah_log $caltech_log`; # so that they can be deleted by script

}


__END__

=head2 NAME - geneace_check.pl

=head3 <USAGE>


=head2 Options: [h or help] [d or debug] [c or class] [a or ace]

            All options have single letter or wordy aliases

B<-help:>
            Displays usage of the script: surprised?

B<-debug:>
            Debug mode, follow by user name, eg. -d ck1 or -debug ck1

            This allows checking results mailed only to the user,
            otherwise results would email to the gangs of Sanger
            Wormbase group and Caltech (Erich)

B<-class:>
            Allows checking only specified classes in Geneace.
            All classes will be checked without this option.
            Choosing multiple classes is supported.
            Class names are case insensitive.
            Current valid options to check these classes are:

               gene
               allele
               laboratory
               strain
               rearrangement
               evidence
               mapping
               xref
               gmap
               multipt

            For example: -c allele -c locus OR -class sequence -class rearrangment

B<-databse:>
            Allows specifying path to a specific database.
            Default database path is /wormsrv1/geneace without this option.

            For example: -db /wormsrv2/autoace or -database /wormsrv1/someone/Test_DB


B<-ace:>
            Allows generating ace file for fixing erros spotted by
            this checking script.
            Default location and filename of ace file:
            /wormsrv1/geneace/CHECKS/geneace_check.rundate.processid.ace
            For example: -a or -ace


B<-verbose:>
            Toggles on extra output.   Useful when running on command line and not on crob job
            For the locus class it will display each locus name as it is processes it and show
            (next to the locus name) a dot for each error it had found in that locus

B<-xref:>
            This option is used to check mysterious two-way XREF problem 
            in AceDB for Geneace, ie, when a sequence under Genomic_
            sequence tag is deleted from a locus object, that sequence obj.
            in Sequence class is still linked to that locus.

            This has caused problem when dumping out the whole database 
            and back in again, because old data made their way back again due
            to XREF, which should have been gone.

            The check also looks for bogus XREF links from Pseudogene 
            and Transcript classes. For instance, when a Pseudogene seq is
            connected to a locus, which later became a CDS, the locus - seq
            link from that Pseudogene obj. in Pseudogene class is still there,
            causing the same problem.

=head3 <RUN geneace_check.pl>

            Geneace check is now set to run on Sundays.
            ##Run Geneace check over weekend
            20 7 * * 0 /wormsrv2/scripts/GENEACE/geneace_check.pl -a &
