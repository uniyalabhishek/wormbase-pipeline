#!/usr/local/bin/perl5.8.0 -w
#
# further_BLAST_dump.pl
#
# script to copy files resulting from blast pipeline on acari to wormsrv2
#
# Author: Chao-Kung CHen
#
# Last updated by: $Author: ar2 $                      
# Last updated on: $Date: 2004-01-22 11:05:00 $        

use strict;
use lib "/wormsrv2/scripts/";
use Wormbase;

my $acari_dir    = "/acari/work2a/wormpipe/dumps";
my $wormsrv2_dir = "/wormsrv2/wormbase/ensembl_dumps";

my @files        = ("worm_pep_blastp.ace",
		    "worm_brigpep_blastp.ace",
		    "worm_dna_blastx.ace",
		    "worm_pep_motif_info.ace",
		    "worm_brigpep_motif_info.ace",
		    "swissproteins.ace",
		    "tremblproteins.ace",
		    "ipi_hits.ace",
		    "worm_pep_best_blastp_hits",
		    "worm_brigpep_best_blastp_hits",
		   );


# make backup directory on wormsrv2
chdir "$wormsrv2_dir";
&run_command("mkdir $wormsrv2_dir/BACKUP") unless (-e "${wormsrv2_dir}/BACKUP");


# backup each file first, then copy across new file
foreach my $file (@files){
  &run_command("mv -f $file ${wormsrv2_dir}/BACKUP/$file");
  &run_command("/usr/apps/bin/scp ${acari_dir}/${file} wormsrv2:${wormsrv2_dir}/${file}");
}


# Also move big ensembl_protein file to BACKUP dir before making new one.
&run_command("mv -f $wormsrv2_dir/ensembl_protein_info.ace $wormsrv2_dir/BACKUP/ensembl_protein_info.ace.backup");
&run_command("cat ipi_hits.ace gadfly.ace yeast.ace swissproteins.ace tremblproteins.ace brigpep.ace > ensembl_protein_info.ace");

exit(0);


##################################################################################################################


sub run_command{
  my $command = shift;
  my $status = system($command);
  if($status != 0){
    print "ERROR: $command failed\n";
  }

  # for optional further testing by calling subroutine
  return($status);
}
