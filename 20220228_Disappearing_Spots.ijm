//Get the home and image directories for this project
homeFolder = getDirectory("Select the Home Directory for This Project");
rawFolder = getDirectory("Select the Directory with the Raw Images");

//Sets Expandable Arrays as True in Case Necessary Later
setOption("ExpandableArrays", true);

//Checks for the presence of the additional folders needed for this project
//Created the folders if they don't already exist
driftFolder = homeFolder + "Drift/";
if (File.isDirectory(driftFolder) < 1) {
	File.makeDirectory(driftFolder); 
}
processedFolder = homeFolder + "Processed/";
if (File.isDirectory(processedFolder) < 1) {
	File.makeDirectory(processedFolder); 
}
segmentedFolder = homeFolder + "Segmented/";
if (File.isDirectory(segmentedFolder) < 1) {
	File.makeDirectory(segmentedFolder); 
}
roiFolder = homeFolder + "ROI/";
if (File.isDirectory(roiFolder) < 1) {
	File.makeDirectory(roiFolder); 
}
resultsFolder = homeFolder + "Results/";
if (File.isDirectory(resultsFolder) < 1) {
	File.makeDirectory(resultsFolder); 
}
resultsNNDFolder = homeFolder + "Results_NND/";
if (File.isDirectory(resultsNNDFolder) < 1) {
	File.makeDirectory(resultsNNDFolder); 
}


//Returns a list of files from the Raw Image Folder Defined by the User
list = getFileList(rawFolder);
l = list.length;
//Processes the first image in each stack to give images suitable for segmentation
for (i=0; i<l; i++) {
	filename = rawFolder + list[i];
	open(filename);
	orig = getTitle();
	//Runs Drift Correction on the Image Timelapse
	run("Correct 3D drift", "channel=1 multi_time_scale sub_pixel only=0 lowest=1 highest=1 max_shift_x=2.000000000 max_shift_y=2.000000000 max_shift_z=1");
	//Saves Drift-Corrected Time Lapse
	saveName = driftFolder + list[i];
	saveAs("Tiff", saveName);
	//Deletes Initial Additional Channel if Necessary
	run("Delete Slice", "delete=channel");
	//Removes All but the First 3 Timepoints from the Drift-Corrected TimeLapse
	run("Slice Remover", "first=4 last=250 increment=1");
	//Runs a small 3D blur function to the 3 slices
	run("Gaussian Blur 3D...", "x=1 y=1 z=1");
	//Creates single plane maximum intensity projection of the 3 slices
	run("Z Project...", "projection=[Average Intensity]");
	//Enhances contrast of the maximum projection and Applies to the Image
	run("Enhance Contrast", "saturated=0.15");
	run("Apply LUT", "slice");
	//Converts the Image to 8-bit for further processing and segmentation
	run("8-bit");
	//Saves the 8-bit maximum intensity projection
	saveName = processedFolder + list[i];
	saveAs("Tiff", saveName);
	//Closes all windows open during this loop
	close();
	selectWindow(orig);
	close();
	close();
}

//Segments the single slice and analyses particles to define the regions of 
//interest for the remainder of the experiment
for (i=0; i<l; i++) {
	//Opens the saved maximum intensity projection from previous loop
	filename = processedFolder + list[i];
	open(filename);
	//Performs Find Maxima function to identify spots of high intensity relative to background
	run("Find Maxima...", "prominence=20 output=[Single Points]");
	//Dilates each spot by 1 pixel in X and Y axes to create a region to be assessed
	run("Dilate");
	saveName = segmentedFolder + list[i];
	saveFileRaw = substring(list[i], 0, (lengthOf(list[i])-4));
	//Runs analyse particles function to identify regions of interest based on the segmented image
	run("Analyze Particles...", "circularity=0.8-1.00 add");
	//Saves the regions of interest
	roiSaveName = roiFolder + saveFileRaw + ".zip";
	count = roiManager("Count");
	if (count > 0) {
		roiManager("save", roiSaveName);
		roiManager("reset");
	}
	//Saves the segmented image
	saveAs("Tiff", saveName);
	close();
}

//Opens the original stacks and and their associated ROI file and 
//measures each ROI over the stack duration, outputting together as a single
//csv file for graphing and analysis
list = getFileList(driftFolder);
l = list.length;
print("I've detected this many images to analyse:    " + l);
row = 0;
for (b=0; b<l; b++) {
	//Opens the drift-corrected timelapse
	filename = driftFolder + list[b];
	open(filename);
	name = getTitle();
	saveFileRaw = substring(list[b], 0, (lengthOf(list[b])-4));
	roiName = roiFolder + saveFileRaw + ".zip";
	if( File.exists(roiName)){
		//Opens the relevant region of interest file for an image, as long as it exists
    	print("This file exists");
		roiManager("open", roiName);
		//Counts the number of spots within the region of interest manager
		n = roiManager("count");
		print(n);
		len = nSlices;
		print("entering ROI Loop");
		//The following loop runs through each region of interest in the ROI manager
		//Assessing the fluorescence intensity within each spot over the duration of the time lapse
		//Storing output information within the Results window
		for (i=0; i<n; i++) {
			//Sets the slice as 1 for the analysis to begin
			setSlice(1);
			//Measures the intensity of the whole image at this initial time point and stores as a variable
			run("Measure");
			averageBase = getResult("Mean");
			//Deletes this temporary result line from the results window
			IJ.deleteRows( nResults-1, nResults-1 );
			//Selects a region within the ROI manager
			roiManager("Select", i);
			//Measures the intensity of fluorescence within this region and stores as a variable
			run("Measure");
			spotBase = getResult("Mean");
			//Deletes the temporary measurement from the results window
			IJ.deleteRows( nResults-1, nResults-1 );
			//Declares the variables for determining spot intensity drop-off prior to analysis
			dropCount = 0;
			dropState = 0;
			dropEnd = 0;
			//Runs through each slice of the image, measuring the fluorescence intensity within the selected spot
			for (j=1; j<len+1; j++) {
				//Sets the slice for region measurement
				setSlice(j);
				//Ensures the correct region is selected
				roiManager("Select", i);
				//Measures the intensity of the selected region
				roiManager("Measure");
				//Adds additional measures the the measurement results window for later ease of analysis
				setResult("Image", row, name);
				setResult("Spot", row, i);
				setResult("Slice", row, j);
				relativeMean = getResult("Mean", row) - averageBase;
				relativeInt = ((getResult("Mean", row))/(spotBase))*100;
				//Checks if the region being assessed has dropped-off or not, recording the outcome in the results window
				if (dropEnd == 1) {
					dropState = 0;
				}
				if (dropEnd == 0) {
					if (relativeInt < 75) {
						dropCount = dropCount + 1;
					}
					else {
						dropCount = 0;
					}
					if (dropCount > 4) {
						dropState = 1;
						dropEnd = 1;
					}
				}
				//Adds additional measures the the measurement results window for later ease of analysis
				setResult("Relative_Intensity", row, relativeInt);
				setResult("Relative_Mean", row, relativeMean);
				setResult("Drop_Detected", row, dropState);
				row = row + 1;
			}
		}
		}
	//Closes open drift-corrected image
	close();
	//Resets the region of interest manager to allow for loading of the next region file
	roiManager("reset");
}
//Saves the results into one big collated csv file
saveAs("Results", resultsFolder + "Collated_Spot_Intensity_Results.csv");

//Clears the results from the previous analysis
run("Clear Results");

//Nearest Distance Analysis Code measures the distance between particles identified within the drift-corrected images
//Note this requires the NND plugin installed prior to macro running to work without an error message
list = getFileList(driftFolder);
l = list.length;
row = 0;
for (b=0; b<l; b++) {
	//Opens the image from the drift-corrected folder
	filename = driftFolder + list[b];
	open(filename);
	name = getTitle();
	saveFileRaw = substring(list[b], 0, (lengthOf(list[b])-4));
	roiName = roiFolder + saveFileRaw + ".zip";
	roiManager("reset");
	//Opens the relevant ROI folder if one exists
	if( File.exists(roiName)){
    	print("This file exists");
		roiManager("open", roiName);
		run("Select All");
		roiManager("Measure");
		roiManager("reset");
		//Runs the nearest neighbour distance analysis plugin to determine nearest neighbour distances
		run("Nnd ");
		//Saves the results, individual file for each image analysed
		saveAs("Results", resultsNNDFolder + saveFileRaw + "_Nearest_Distance.csv");
		run("Clear Results");
	}
	close();
}