
package GenomeBrowser::Deployment;
use LWP;
use File::Basename;
use Carp;
# Be in EBI
# Have tunnels enabled
# Then you can do everything

our $SANGER_HOST="sangerngs"; # Made up ssh alias

our $EBI_PATH="/nfs/ftp/pub/databases/arrayexpress/data/atlas/rnaseq";
our $EBI_URL="ftp://ftp.ebi.ac.uk/pub/databases/arrayexpress/data/atlas/rnaseq";
our $SANGER_PATH="/data/production/parasites/rnaseqer";
our $SANGER_URL="https://ngs.sanger.ac.uk/production/parasites/rnaseqer";

sub location {
  my ( $root, $species, $assembly, $run_id ) = @_;
  (my $prefix = $run_id) =~ s/(.{6}).*/$1/;
  return join "/", $root, $species, $assembly, $prefix, "$run_id.bw";
}
sub run_in_sanger {
  my $cmd = "ssh $SANGER_HOST ".shift;
  `$cmd`;
  croak "Failed: $cmd" if $?;
}
sub sync_ebi_to_sanger {
  my ($species, $assembly, $run_id, $source_url, %opts) = @_;
  my $target_path = location ($SANGER_PATH, $run_id);
  my $target_dir = dirname $target_path;

  if ($opts{do_sync} // not file_is_online($run_id)){
    run_in_sanger("mkdir -p $target_dir");
    run_in_sanger("wget --continue --no-verbose -O $target_path $source_url");
  } else {
    print STDERR "Skipping sync: $run_id\n" if $ENV{DEPLOYMENT_VERBOSE};
  }
  return location($SANGER_URL, $run_id); 
}

sub file_present_at_sanger {
  my $path = location ($SANGER_PATH, shift);
  system("ssh $SANGER_HOST ls $path > /dev/null 2>&1");
  return 0 == $?;
}

sub file_is_online {
  my $path = location($SANGER_URL, shift);
  return LWP::UserAgent->new->head($path)->is_success;
}
1;
