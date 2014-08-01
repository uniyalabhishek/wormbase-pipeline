#!/bin/env perl
#===============================================================================
#
#         FILE:  get_all_elegans_orthologues.pl
#
#      CREATED:  03/08/06 13:26:19 BST (mh6@sanger.ac.uk)
#===============================================================================

use strict;
use Wormbase;
use Log_files;
use IO::File;
use Bio::EnsEMBL::Compara::DBSQL::DBAdaptor;

use Getopt::Long;

my ($verbose,$new,$debug,$test,$store,$outfile,$other);

my $comparadb = 'worm_compara';
my $dbhost    = $ENV{'WORM_DBHOST'};
my $dbuser    = 'wormro';
my $dbport    = $ENV{'WORM_DBPORT'};

GetOptions(
  'database=s' => \$comparadb,
  'dbhost=s'   => \$dbhost,
  'dbuser=s'   => \$dbuser,
  'dbport=s'   => \$dbport,
  'verbose'    => \$verbose,
  'debug=s'    => \$debug,
  'test'       => \$test,
  'store=s'    => \$store,
  'outfile=s'  => \$outfile,
  'other=s'    => \$other, # Ortholog_other
) || die("cant parse the command line parameter\n");


my (%species, %t3_pep);

my %core_species = ('caenorhabditis_elegans'  => 1,
                    'caenorhabditis_briggsae' => 1,
                    'caenorhabditis_remanei'  => 1,
                    'caenorhabditis_brenneri' => 1,
                    'caenorhabditis_japonica' => 1,
                    'pristionchus_pacificus'  => 1,
                    'brugia_malayi'           => 1,
                    'onchocerca_volvulus'     => 1);

my %cds2wbgene=%{&get_commondata('cds2wbgene_id')};

my $wormbase;

if ($store){
 $wormbase = Storable::retrieve($store)
      or croak("cannot restore wormbase from $store"); 
}else{
 $wormbase = Wormbase->new(
    -test    => $test,
    -debug   => $debug,
 )
}

$outfile ||= $wormbase->acefiles . '/compara.ace';
$other ||= $wormbase->acefiles . '/compara_other.ace';

# establish log file.
my $log = Log_files->make_build_log($wormbase);


my $compara_db = new Bio::EnsEMBL::Compara::DBSQL::DBAdaptor(
    -host   => $dbhost,
    -user   => $dbuser,
    -port   => $dbport,
    -dbname => $comparadb
) or die(@!);

my $gdb_adaptor = $compara_db->get_GenomeDBAdaptor;
my $member_adaptor = $compara_db->get_GeneMemberAdaptor();
my $homology_adaptor = $compara_db->get_HomologyAdaptor();

my @genome_dbs = @{$gdb_adaptor->fetch_all};
foreach my $gdb (@genome_dbs) {
  my $node = $compara_db->get_NCBITaxonAdaptor->fetch_node_by_genome_db_id($gdb->dbID);

  my $name = $node->name;

  # special cases: C. sp5 and C. sp11
  if ($name =~ /sp\. 5 DRD-2008/) {
    $name = "Caenorhabditis sp.5"; 
  } elsif ($name =~ /\s+csp11$/) {
    $name = "Caenorhabditis tropicalis";
  }

  $species{$gdb->dbID} = $name;

}

my $outfh = IO::File->new($outfile,'w')||die(@!);
my $otherfh = IO::File->new($other,'w')||die(@!);

foreach my $gdb1 (@genome_dbs) {
#   next if not exists $core_species{$gdb1->name};
 
  $log->write_to("Processing " . $gdb1->name . "...\n") if $verbose;

  my (%homols);

  foreach my $gdb2 (@genome_dbs) {

    $log->write_to("   Comparing to " . $gdb2->name . "...\n") if $verbose;

    my $mlss;
    if ($gdb1->dbID == $gdb2->dbID) {
      $mlss = $compara_db->get_MethodLinkSpeciesSetAdaptor->fetch_by_method_link_type_GenomeDBs('ENSEMBL_PARALOGUES', [$gdb1]);      
    } else {
      $mlss = $compara_db->get_MethodLinkSpeciesSetAdaptor->fetch_by_method_link_type_GenomeDBs('ENSEMBL_ORTHOLOGUES', [$gdb1, $gdb2]);
    }
    
    my @homologies = @{$homology_adaptor->fetch_all_by_MethodLinkSpeciesSet( $mlss )};

    foreach my $homology (@homologies) {
      
      my ($m1, $m2) = sort { $a->stable_id cmp $b->stable_id } @{ $homology->get_all_Members };
      
      if ($m1->genome_db->dbID != $gdb1->dbID) {
        # members have been returned in the wrong order, so swap them
        ($m2, $m1) = ($m1, $m2);
      }        
      
      my $gid1 = $cds2wbgene{$m1->stable_id}?$cds2wbgene{$m1->stable_id}:$m1->stable_id;
      my $gid2 = $cds2wbgene{$m2->stable_id}?$cds2wbgene{$m2->stable_id}:$m2->stable_id;

      $gid1 = $gdb1->taxon_id().':'.$gid1 if not exists $core_species{$gdb1->name};
      $gid2 = $gdb2->taxon_id().':'.$gid2 if not exists $core_species{$gdb2->name};
     
      my $m2pep = $m2->gene_member->get_canonical_SeqMember;
      

      if ($gdb1->dbID == $gdb2->dbID) {
          # we need to add the connection both ways, so that that evidence gets added to both
          $homols{$gid1}->{Paralog}->{$species{$gdb2->dbID}}->{$gid2} = 1;
          $homols{$gid2}->{Paralog}->{$species{$gdb1->dbID}}->{$gid1} = 1;
      } else {
          $homols{$gid1}->{Ortholog}->{$species{$gdb2->dbID}}->{$gid2} = $species{$gdb2->dbID};
      }

      unless (exists $core_species{$gdb2->name}) {
        $homols{$gid1}->{Ortholog_other}->{$species{$gdb2->dbID}}->{$m2pep->stable_id} = 1;
        if (not exists $t3_pep{$m2pep->stable_id}) {
          $t3_pep{$gdb2->dbID}->{$m2pep->stable_id} = $m2pep->sequence;
        }
      }
    } 
  }
    
  print $outfh "// Homologies for " . $gdb1->name . "\n\n";

  foreach my $g (sort keys %homols) {
    
    print $outfh "\nGene : \"$g\"\n";
    
    foreach my $tag_group (keys %{$homols{$g}}) {
      foreach my $spe (sort keys %{$homols{$g}->{$tag_group}}) {
        foreach my $entity (sort keys %{$homols{$g}->{$tag_group}->{$spe}}) {
          if ($tag_group =~ /other/) {
            print $otherfh "Gene : \"$g\"\n";
            print $otherfh "$tag_group \"$entity\" From_analysis WormBase-Compara\n\n";
          } else {
            print $outfh "$tag_group \"$entity\" \"$spe\" From_analysis WormBase-Compara\n";
          }
        }
      }
    }
  }   
}

$log->mail;

#################
# also adds the sequence name of the parent gene
sub get_commondata {
    my ($name)=@_;
    my %genehash;
    my @locations=qw(autoace remanei briggsae pristionchus japonica brenneri brugia ovolvulus);
    my $dir='/nfs/panda/ensemblgenomes/wormbase/BUILD/';
      
    foreach my $loc(@locations) {
        my $file_name="$dir/$loc/COMMON_DATA/$name.dat";
	my $file= new IO::File "< $file_name" || die("@! can't open $file_name");
        $/=undef;
        my $data=<$file>;
        $/="\n";
        $file->close;
        my $VAR1;
        eval($data);

        while(my ($k,$v)=each(%{$VAR1})){
            $genehash{$k}=$v;
            $k=~s/[a-z]$//;
            $genehash{$k}=$v;
        }
    }
    return \%genehash;
}
