require "subfuncs.pl";
use Bio::SeqIO;
use Bio::TreeIO;
use Bio::Root::Test;
use PostScript::Simple;
use Bio::Align::Utilities qw(cat);
use Bio::Tools::Run::Phylo::Hyphy::REL;
use Bio::Tools::Run::Phylo::Hyphy::BatchFile;
use Bio::Tools::Run::Phylo::Hyphy::SLAC;
use File::Basename;
use Getopt::Long;

my $usage = "perl " . basename($0);
$usage .= " gb_file fa_file tree_file output_name\n";

my $gb_file = shift or die $usage;
my $fa_file = shift or die $usage;
my $tree_file = shift or die $usage;
my $output_name = shift or die $usage;
#GetOptions ('query=s' => \$queryfile, 'subject=s' => \$subjectfile);



my $whole_aln = make_aln_from_fasta_file ($fa_file);
my @gene_alns;

my $seqio_object = Bio::SeqIO->new(-file => $gb_file);
my $seq_object = $seqio_object->next_seq;

while ($seq_object) {
	for my $feat_object ($seq_object->get_SeqFeatures) {
		if ($feat_object->primary_tag eq "CDS") {
			my $name = main_name_for_gb_feature($feat_object);
			# no point dealing with this feature if it doesn't have a name...
			if ($name eq "") { next; }
			my @locations = $feat_object->location->each_Location;
			my $cat_aln = 0;
			my $strand = 0;
			foreach $loc (@locations) {
				$strand = $loc->strand;
				my $start = $loc->start;
				my $end = $loc->end;
				my $curr_slice = $whole_aln->slice($start, $end);
				if ($cat_aln == 0) {
					$cat_aln = $curr_slice;
				} else {
					$cat_aln = cat($cat_aln, $curr_slice);
				}
			}
			if ($strand < 0) {
				# must flip each seq in the curr_slice
				my $flipped_aln = Bio::SimpleAlign->new();
				foreach $seq ( $cat_aln->each_seq() ) {
					$seq = $seq->revcom();
					$flipped_aln->add_seq($seq);
				}
				$cat_aln = $flipped_aln;
			}

			$cat_aln = $cat_aln->slice(1, $cat_aln->length()-3);
			$cat_aln->description($name);
			push @gene_alns, $cat_aln;
		}
	}
	$seq_object = $seqio_object->next_seq;
}


my $treeio = Bio::TreeIO->new(-format => "nexus", -file => "$tree_file");
#read in all of the trees
my %trees = ();
my $tree = $treeio->next_tree;
my $firsttree = $tree;

while ($tree) {
	$trees{$tree->id()} = $tree;
	$tree = $treeio->next_tree;
}
open OUT_FH, ">", "$output_name.lrt";
print OUT_FH "gene\tHa=single omega\tHa=local omegas\tglobal omega\n";
foreach my $aln (@gene_alns) {
	my $name = $aln->description();
	print "getting model for $name...";
	my $bf_exec = Bio::Tools::Run::Phylo::Hyphy::BatchFile->new(-params => {'bf' => "ModelTest.bf", 'order' => [$aln, $firsttree, '4', 'AIC Test',  "$output_name"."_$name.aic"]});
	my $resultstr = $name;
 	$bf_exec->alignment($aln);
 	if ($trees{$name} == undef) {
 		print "skipping $name because tree is not available\n";
 		next;
 	}
 	if (keys(%trees) != 1) {
		$bf_exec->tree($trees{$name}, {'branchLengths' => 1 });
		#print "using " . $trees{$name}->id() . " for tree\n";
	}
 	$bf_exec->outfile_name("$output_name"."_$name.bfout");
 	my ($rc,$parser) = $bf_exec->run();
	if ($rc == 0) {
		my $t = $bf_exec->error_string();
		print ">>" . $t . "\n";
	}
	open FH, "<", $bf_exec->outfile_name();
	my @output_fh = <FH>;
	close FH;

	my $output = join("\n", @output_fh);
	$output =~ m/Model String:(\d+)/g;
	my $model = $1;
	print "$model chosen.\n";
	print "running LRTs on $name...\n";
	$bf_exec = Bio::Tools::Run::Phylo::Hyphy::BatchFile->new(-params => {'bf' => "", 'order' => ["Universal", $bf_exec->alignment, $model, $bf_exec->tree]});
# 	$bf_exec->save_tempfiles(1);
	$bf_exec->alignment($aln);
	$bf_exec->tree($trees{$name}, {'branchLengths' => 1 });
	$bf_exec->outfile_name("$output_name"."_$name.bfout");
	my $bf = $bf_exec->make_batchfile_with_contents(batchfile_text());
 	my ($rc,$parser) = $bf_exec->run();
	if ($rc == 0) {
		my $t = $bf_exec->error_string();
		print "There was an error: " . $t . "\n";
	}
	open FH, "<", $bf_exec->outfile_name();
	my @output_fh = <FH>;
	close FH;

	my $output = join("\n", @output_fh);
	$output =~ m/Global omega calculated to be (.+?)\n/g;
	my $omega = $1;
	$output =~ m/LRT for single omega across the tree: p-value = (.+?),/g;
	my $p_value1 = $1;
	$output =~ m/LRT for variable omega across the tree: p-value = (.+?),/g;
	my $p_value2 = $1;
	print OUT_FH "$name\t$p_value1\t$p_value2\t$omega\n";
}

sub temp_batchfile {

}

sub batchfile_text {
    return qq{
RequireVersion ("0.9920060830");
VERBOSITY_LEVEL = -1;

ExecuteAFile (HYPHY_LIB_DIRECTORY+"TemplateBatchFiles"+DIRECTORY_SEPARATOR+"Utility"+DIRECTORY_SEPARATOR+"DescriptiveStatistics.bf");
ExecuteAFile (HYPHY_LIB_DIRECTORY+"TemplateBatchFiles"+DIRECTORY_SEPARATOR+"TemplateModels"+DIRECTORY_SEPARATOR+"chooseGeneticCode.def");

ModelMatrixDimension = 64;
for (k=0; k<64; k=k+1)
{
	if (_Genetic_Code[k] == 10)
	{
		ModelMatrixDimension = ModelMatrixDimension -1;
	}
}

ExecuteAFile (HYPHY_LIB_DIRECTORY+"TemplateBatchFiles"+DIRECTORY_SEPARATOR+"2RatesAnalyses"+DIRECTORY_SEPARATOR+"MG94xREV.mdl");

SetDialogPrompt     ("Choose a nucleotide alignment");
DataSet ds        = ReadDataFile (PROMPT_FOR_FILE);

DataSetFilter	  	filteredData = CreateFilter (ds,3,"","",GeneticCodeExclusions);

SKIP_MODEL_PARAMETER_LIST = 1;
done 					  = 0;

while (!done)
{
	fprintf (stdout,"\nPlease enter a 6 character model designation (e.g:010010 defines HKY85):");
	fscanf  (stdin,"String", modelDesc);
	if (Abs(modelDesc)==6)
	{
		done = 1;
	}
}
modelType 				  = 0;
ExecuteAFile (HYPHY_LIB_DIRECTORY+"TemplateBatchFiles"+DIRECTORY_SEPARATOR+"TemplateModels"+DIRECTORY_SEPARATOR+"MG94custom.mdl");
SKIP_MODEL_PARAMETER_LIST = 0;

ExecuteAFile 		(HYPHY_LIB_DIRECTORY+"TemplateBatchFiles"+DIRECTORY_SEPARATOR+"queryTree.bf");

brNames				= BranchName (givenTree,-1);
COVARIANCE_PARAMETER 				= {};
global global_OMEGA = 1;
for (k=0; k < Columns (brNames)-1; k=k+1)
{
	ExecuteCommands ("givenTree."+brNames[k]+".nonSynRate:=givenTree."+brNames[k]+".omega*givenTree."+brNames[k]+".synRate;");
	COVARIANCE_PARAMETER["givenTree."+brNames[k]+".omega"] = 1;
}

LikelihoodFunction  theLnLik = (filteredData, givenTree);


for (k=0; k < Columns (brNames)-1; k=k+1)
{
//  set all of the branches to have omega constrained to the same global_OMEGA
	ExecuteCommands ("givenTree."+brNames[k]+".omega:=global_OMEGA;");
}

fprintf 					   (stdout, "\nFitting the global model to the data...\n");
Optimize 					   (res_global, theLnLik);
fprintf						   (stdout, theLnLik,"\n\n");
global omega_MLE = global_OMEGA;

for (k=0; k < Columns (brNames)-1; k=k+1)
{
//  set each branch to have unconstrained omega
	ExecuteCommands ("givenTree."+brNames[k]+".omega=global_OMEGA;");
}

fprintf 					   (stdout, "\nFitting the local model to the data...\n");
Optimize 					   (res_local, theLnLik);
fprintf						   (stdout, theLnLik,"\n\n");

for (k=0; k < Columns (brNames)-1; k=k+1)
{
//  set each branch to have omega = 1
	ExecuteCommands ("givenTree."+brNames[k]+".omega:=1;");
}

fprintf 					   (stdout, "\nFitting the neutral model to the data...\n");
Optimize 					   (res_neutral, theLnLik);
fprintf						   (stdout, theLnLik,"\n\n");

fprintf (stdout, "\nGlobal omega calculated to be ", omega_MLE, "\n");

LR = 2(res_global[1][0]-res_neutral[1][0]);
DF = res_global[1][1]-res_neutral[1][1];

fprintf (stdout, "\nLRT for single omega across the tree: p-value = ", 1-CChi2(LR,DF), ", LR = ", LR, ", Constraints = ", DF, "\n\n");

LR = 2(res_local[1][0]-res_global[1][0]);
DF = res_local[1][1]-res_global[1][1];

fprintf (stdout, "\nLRT for variable omega across the tree: p-value = ", 1-CChi2(LR,DF), ", LR = ", LR, ", Constraints = ", DF, "\n\n");

COVARIANCE_PRECISION = 0.95;
CovarianceMatrix (covMx, theLnLik);
//
VERBOSITY_LEVEL = 0;
//
for (k=0; k < Columns (brNames)-1; k=k+1)
{
	fprintf (stdout, "Branch :", brNames[k], "\n\tomega MLE = ", Format (covMx[k][1],6,3), "\n\t95% CI = (",Format (covMx[k][0],6,3), ",", Format (covMx[k][2],6,3), ")\n");
}

    };
}