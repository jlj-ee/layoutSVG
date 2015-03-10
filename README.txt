README:

layoutSVG.il 
@author Jaime Jimenez
jaime.jimenez.ee@gmail.com
March 2015

Version: 1.0

Tested on Cadence Virtuoso 6.1.5 using the AMS H18 technology library

--- CREDITS -----------------------------------------------------------------------------------------------------------------

Thanks to Matthew Beckler for his help and for writing another layout-to-SVG solution (http://www.mbeckler.org/cadence_plot/).
Unfortunately, Virtuoso 6.1.5 no longer supports the ASCII dump that his Python script requires. 

Thanks to Roger Light on edaboard (http://www.edaboard.co.uk/layout-to-svg-t176680.html). 
His SKILL script is no longer compatible with 6.1.5, but it formed a basis for this utility.

--- DESCRIPTION -------------------------------------------------------------------------------------------------------------

This script was written to create high-quality vector images from Virtuoso layout files.
After configuring the necessary paths and *.layers and *.style files (see below), 
running the script will generate an SVG file from the current layout with only the 
currently visible layers.

To run:
In the Cadence console, type the following without quotes: 	
"load <path>/LayoutSVG.il"   (replace <path> with the correct path to this file)
"MakeSVG()""

--- CONFIGURATION -----------------------------------------------------------------------------------------------------------

Two external files are needed to configure the SVG creation.
1. 	A *.style file (replace * with the desired filename). This determines how the layers will look.
	For example:

	.M1drawing 	{fill:#0000ff; fill-opacity:0.3; stroke:#0000ff; stroke-width:2; stroke-opacity:1}

	The line begins with the layer name and purpose concatenated together. The curly brackets enclose 
	the SVG style options for painting and can include many other attributes: (http://www.w3.org/TR/SVG/painting.html)
	Experiment to see what looks best to you!
	The contents of *.style will be copied directly into the final SVG.

	Layers in the layout file without a corresponding line in *.style will appear as black boxes.
	Also, typos in *.style will cause black boxes.

2. 	A *.layers file (replace * with the desired filename). This determines the order in which the layers are painted.
	For example:

	V2 drawing
	M3 drawing
	V1 drawing
	M2 drawing
	M1 drawing

	The layer at the top will be highest in the SVG. Thus, the order above will ensure that vias are not hidden
	between their corresponding metal layers. Note that layers within an individual cell will be in the correct order,
	but cells within that cell will be entirely below the shape layers regardless of what layers they contain. 

	A layer will only be painted if it is listed in this file AND marked as visible in the layer selection window in Virtuoso.

Also, you must edit MakeSVG() below:
1. 	Set SCALE to change how big the final geometry will be. You may need to experiment with this value to get something that 
	looks good for your particular layout.
2. 	Set the string in SVGFile to the directory where you want your .svg file to be saved. Avoid using relative paths (i.e. ../)
3. 	Set styleFile equal to a string of the path to your *.style file. Avoid using relative paths (i.e. ../)
4. 	Set layersFile equal to a string of the path to your *.layers file. Avoid using relative paths (i.e. ../)

--- ADDITIONAL NOTES --------------------------------------------------------------------------------------------------------

*	A temporary library is created to protect the original layout file AND to allow flattening
	of pcells and mosaics level-by-level. Although the cells in the temporary library get deleted,
	the library itself does not because it causes problems.
  	You can set it to be deleted by searching for the FIXME line below.

*	If anything goes wrong, the cells in the temporary library will not get deleted, which can
	cause problems on subsequent executions of the program. Browse with the Library manager to 
	delete these files.

* 	The only supported layout shapes in this version are path/rectangle/polygon.

* 	Labels are not currently supported because in my experience it ends up looking cluttered.
	An SVG file can be easily edited to add only the labels you want.
	Free editing software: Inkscape (https://inkscape.org/en/) 