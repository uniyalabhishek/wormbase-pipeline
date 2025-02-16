#!/usr/bin/env perl

use strict;
use warnings;
use ProductionMysql;
use File::Slurp qw/write_file/;


my %species_to_skip_from_compara = map {$_ => 1}
qw/haemonchus_contortus_prjna205202
heligmosomoides_polygyrus_prjeb1203
macrostomum_lignano_prjna284736
onchocerca_flexuosa_prjeb512
schmidtea_mediterranea_prjna12585
taenia_asiatica_prjeb532
trichinella_pseudospiralis_iss141prjna257433
trichinella_pseudospiralis_iss176prjna257433
trichinella_pseudospiralis_iss470prjna257433
trichinella_pseudospiralis_iss588prjna257433
toxocara_canis_prjeb533
ancylostoma_ceylanicum_prjna72583
angiostrongylus_cantonensis_prjeb493
ascaris_suum_prjna80881
caenorhabditis_remanei_prjna248909
caenorhabditis_remanei_prjna248911
clonorchis_sinensis_prjda72781
dictyocaulus_viviparus_prjeb5116
hymenolepis_diminuta_prjeb507
loa_loa_prjna37757
meloidogyne_arenaria_prjeb8714
meloidogyne_arenaria_prjna340324
meloidogyne_floridensis_prjeb6016
meloidogyne_incognita_prjna340324
meloidogyne_javanica_prjeb8714
onchocerca_ochengi_prjeb1465
schistosoma_japonicum_prjea34885
steinernema_carpocapsae_v1prjna202318
steinernema_feltiae_prjna204661
trichinella_nativa_prjna179527
trichinella_spiralis_prjna257433
trichuris_suis_prjna208415
trichuris_suis_prjna208416
wuchereria_bancrofti_prjeb536
/;


write_file("$ENV{PARASITE_CONF}/compara.species_list",
  map {"$_\n"} grep {not $species_to_skip_from_compara{$_}} ProductionMysql->staging->species
);
