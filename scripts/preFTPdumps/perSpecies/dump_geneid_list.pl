#!/usr/bin/env perl

use strict;

use IO::File;
use Storable;
use Getopt::Long;

use lib $ENV{CVS_DIR};

use Wormbase;
use Log_files;

my ($store,$debug,$test,$database,$species,$outfile,$other_names);
GetOptions(
       'store=s' => \$store,
       'debug=s' => \$debug,
       'test'    => \$test,
       'species=s'  => \$species,
       'database=s' => \$database,
       'outfile=s'  => \$outfile,
       'other'      => \$other_names
)||die(@!);

my $wormbase;
if ($store) { 
  $wormbase = Storable::retrieve($store) or croak("Can't restore wormbase from $store\n");
} 
else {
  $wormbase = Wormbase->new( -debug => $debug, -test => $test,-autoace=> $database,-organism => $species);
}

my $log = Log_files->make_build_log($wormbase);

$outfile = $wormbase->reports . '/cdna2orf.fa'
    if not defined $outfile;
my $of = IO::File->new($outfile,'w');
$log->write_to("writing to $outfile\n");

my $db = Ace->connect(-path => ($database) ? $database : $wormbase->autoace ) or $log->log_and_die("Could not connect\n");
my $full_name = $wormbase->full_name;
my $tax_id = $wormbase->ncbi_tax_id;

my $gene_it = $db->fetch_many(-query => "Find Gene; Species=\"${full_name}\"");
while(my $gene=$gene_it->next){
  if ($other_names) {
    print $of join("\t",$gene,$gene->Status,$gene->Sequence_name,$gene->CGC_name,$gene->Other_name),"\n";    
  } else {
    print $of join(",", 
                   $tax_id,
                   $gene,
                   ($gene->CGC_name||''),
                   ($gene->Sequence_name||''),
                   $gene->Status), "\n";
    
    
  }
}

$of->close;
$log->mail;
exit(0);
