/*===========================================================================================================================

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
In the Cadence console, type: 	"load <path>/LayoutSVG.il"   (replace <path> with the correct path to this file)
								"MakeSVG()"

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

===========================================================================================================================*/

/* ----------------------------------------------------------------------------------------
//	MakeSVG ()
//
//  This function runs the SVG printing utility. 
//  It must be edited (see CONFIGURATION) above to include the correct paths.
//  
// ---------------------------------------------------------------------------------------- */
(defun MakeSVG ()
	(let (cell currentDir SVGFile styleFile layersFile tempLibName)
		; GLOBAL VAR: Layout scale factor
		SCALE = 200

		; Retrieve current window for processing
		cell = (geGetWindowCellView (hiGetCurrentWindow))
		
		; Destination of svg output file
		SVGFile = (strcat "/home/Jaime/cadence/svg/" cell~>libName "-" cell~>cellName "-" cell~>viewName ".svg")
		
		; Location of style file
		styleFile = "/home/Jaime/cadence/svg/svg.style"
		
		; Location of layers file
		layersFile = "/home/Jaime/cadence/svg/svg.layers"

		; Temporary directory for layout conversion
		tempLibName = "MakeSVGtempLib"

		; Call SVG maker function
		(LayoutToSVG tempLibName cell~>libName cell~>cellName cell~>viewName SVGFile styleFile layersFile)
	)    
)

/* ----------------------------------------------------------------------------------------
//	LayoutToSVG (tempLibName libName cellName viewName SVGFile styleFile layersFile)
//
//  This function constitutes the main layout->SVG printing routine. It creates the temporary
//  library to protect the original files, then flattens the layout hierarchy to print
//  the SVG file.
//
//  tempLibName - name of the temporary directory used for processing
//  libName - name of the library for the original cell
//  cellName - name of the cell to be printed to SVG
//  viewName - name of the view in the cell to be printed to SVG
//  SVGFile - path to the output *.svg file
//  styleFile - path to *.style
//  layersFile - path to *.layers
//  
// ---------------------------------------------------------------------------------------- */
(defun LayoutToSVG (tempLibName libName cellName viewName SVGFile styleFile layersFile)
	(let (techName tempLib cellOriginal cellCopy fOut layerList flatten done_inst offsets)
		; Retrieve the layout cellview in read-only mode
		cellOriginal = (dbOpenCellViewByType libName cellName viewName "maskLayout" "r")

		; Create a temporary library with the correct technology library name
		techName = (techGetTechLibName cellOriginal) 
		(unless tempLib = (ddGetObj tempLibName)
			tempLib = (dbCreateLib tempLibName))
		(techSetTechLibName tempLib techName)

		; Make a copy of the layout cellview for processing
		cellCopy = (dbCopyCellView cellOriginal tempLibName (strcat libName "-" cellName) viewName)
		(dbClose cellOriginal)

		; Build a list using the layer-ordering file
		layerList = (MakeLayerList layersFile)

		/* Begin printing to SVG file ------------------------------------------------------------------------------------ */
		fOut = (outfile SVGFile)

		; Print the SVG header
		offsets = (PrintSVG_Header fOut cellCopy)

		; Print the SVG <style> block
		(PrintSVG_Style fOut styleFile)

		; Flatten the top level (vias, pcells, mosaics, and any geometry created on top of subcells)
		; After this step, cell~>instances only holds subcells which can be added to <defs> for reuse
		(Flatten1L cellCopy)

		; Print the SVG <defs> block
		(PrintSVG_Defs fOut cellCopy tempLibName libName layerList)

		; If necessary, generate <use> statements to instantiate subcells from <defs>
		; Then, print the flattened top-level geometry
		(PrintSVG_ArtMaster fOut cellCopy layerList (car offsets) (cadr offsets))

		; Pirint the SVG footer
		(PrintSVG_Footer fOut)
		(close fOut)
		/* End printing to SVG file -------------------------------------------------------------------------------------- */

		; CLEANUP
		viewName = cellCopy~>viewName
		(ddDeleteObj (ddGetObj tempLibName (strcat libName "-" cellName)))
		
		; FIXME - Removing the temporary library adds "#Removed by ddDeleteObj: Define ..." to cds.lib
		; Sometimes, it also messes with layers in the layer selection window. Uncomment the next line at your own risk
		;(ddDeleteObj tempLib)
		(printf "SVG export of %s/%s/%s to %s complete.\n" libName cellName viewName SVGFile)
	)
)


/* HELPER FUNCTIONS =========================================================================================================
=============================================================================================================================
===========================================================================================================================*/

/* ----------------------------------------------------------------------------------------
//	MakeLayerList (layersFile)
//
//	Outputs a list of strings (layerList) representing the layers from the layout file that 
//  are both visible AND included in *.layers. 
//  This funtion will raise an error on (close fLayers) if layersFile cannot be found.
//  
//  layersFile - the path to *.layers
//  
// ---------------------------------------------------------------------------------------- */
(defun MakeLayerList (layersFile)
	(let (fLayers str layers layerList)
		; Iterate through layers file
		fLayers = (infile layersFile)
		(if fLayers then 
			; Strip off EOL character and make tuple for checking visibility --> i.e. ("M1" "drawing")
			(rexCompile "\n$")
			(while (gets str fLayers)
				str = (parseString (rexReplace str "" 1))
				; Ignore empty lines
				(unless (not str)
					; Ignore hidden layers
					(if (leIsLayerVisible str) then
						; Concatenate ordered pair and add to list --> i.e. ("M1drawing" ...)
						layerList = (cons (strcat (car str) (cadr str)) layerList)
					)
				)
			)
		)
		(close fLayers)
		layerList
	)
)

/* ----------------------------------------------------------------------------------------
//	PrintSVG_Header (fOut cell)
//
//	Outputs a list (offX offY) indicating lower left corner of the bBox of the top-level cell.
//  This will be used to set the origin of cells to (0,0).
//  Prints the SVG header to file with dimension/viewbox calcualted from the layout bBox
//  
//  fOut - handle to the SVG output file
//  cell - handle to the layout cell
//  
// ---------------------------------------------------------------------------------------- */
(defun PrintSVG_Header (fOut cell)
	(let (x1 y1 x2 y2 width height)
		; Compute dimensions from layout bounding box 
		x1 = (xCoord (car cell~>bBox))*SCALE
		y1 = (yCoord (car cell~>bBox))*SCALE
		x2 = (xCoord (cadr cell~>bBox))*SCALE
		y2 = (yCoord (cadr cell~>bBox))*SCALE
		offX = x1
		offY = y1
		width = (x2 - x1)
		height = (y2 - y1)

		; Print SVG header as per http://www.w3.org/TR/SVG/struct.html
    	(fprintf fOut 	"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>\n")
    	(fprintf fOut 	"<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\" \"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">\n")
    	(fprintf fOut 	"<svg\n")
    	(fprintf fOut 	"	xmlns=\"http://www.w3.org/2000/svg\"\n")
    	(fprintf fOut 	"	xmlns:xlink=\"http://www.w3.org/1999/xlink\"\n")
    	(fprintf fOut 	"	version=\"1.0\"\n")
    	(fprintf fOut 	"	width=\"%gpx\"\n" width)
    	(fprintf fOut 	"	height=\"%gpx\"\n" height)
    	(fprintf fOut 	"	viewBox=\"%g %g %g %g\"\n" 0.0 0.0 x2-x1 y2-y1) 
    	(fprintf fOut 	"	id=\"svg2\">\n")
    	(fprintf fOut 	"<title>%s - %s - %s</title><desc></desc>\n" cell~>libName cell~>cellName cell~>viewName)

    	; Return coordinates of lower-left corner.
    	; (offX offY) are used to set the origin of the top cell to 0,0.
    	list(offX offY)
	)
)

/* ----------------------------------------------------------------------------------------
//	PrintSVG_Style (fOut styleFile)
//
//	Uses *.style file to print the SVG style block to the file.
//  This funtion will raise an error on (close fLayers) if layersFile cannot be found.
//  
//  fOut - handle to the SVG output file
//  styleFile - the path to *.style
//  
// ---------------------------------------------------------------------------------------- */
(defun PrintSVG_Style (fOut styleFile)
	(fprintf fOut "<style>\n")
	; Iterate through the style file and print it to the SVG
	(let (fStyle str)
		fStyle = (infile styleFile)
		(if fStyle then
			(while (gets str fStyle)
				(fprintf fOut "%s" str)
			)
		)
		(close fStyle)
	)
	(fprintf fOut "</style>\n")
)

/* ----------------------------------------------------------------------------------------
//	PrintSVG_Defs (fOut cell tempLibName libName layerList)
//
//	Uses *.style file to print the SVG style block to the file.
//  This funtion will raise an error on (close fLayers) if layersFile cannot be found.
//  
//  fOut - handle to the SVG output file
//  cell - handle to the layout cell
//  tempLibName - name of the temporary directory used for processing
//  layerList - list of layers to draw produced by MakeLayerList(..)
//  libName - name of the library for the original cell
//  
// ---------------------------------------------------------------------------------------- */
(defun PrintSVG_Defs (fOut cell tempLibName libName layerList)
	(let (defsList)
		; Begin defs block for reusable cells
		(fprintf fOut "<defs>\n")

		; Anything that is still unflattened is a subcell to add to the defs
		defsList = nil ; List of subcells added to defs
		(foreach subCell cell~>instances
				 defsList = (PrintSVG_DefSubCell fOut tempLibName libName subCell layerList defsList)
		) 
		(fprintf fOut "</defs>\n")
	)
)

/* ----------------------------------------------------------------------------------------
//	Flatten1L (cell)
//
//	Flattens all mosaics, pcells, and vias in the current cell down by one level.
//
//  cell - handle to the layout cell
//
// ---------------------------------------------------------------------------------------- */
(defun Flatten1L (cell)
	(let (flatten)	
		flatten = t
		(while flatten
			flatten = nil
			(foreach inst cell~>instances
				(cond
					; Flatten mosaic
				  	(inst~>objType == "mosaicInst"
						flatten = t
						(dbFlattenInst inst~>mosaic 1)
					)
					; Flatten pcell
				  	(inst~>master~>superMaster != nil
						flatten = t
						(dbFlattenInst inst 1 t)
					)
				)
			)
			; Flatten vias
			(foreach via cell~>vias
				(dbFlattenInst via 1)
			)
		)
	)
)

/* ----------------------------------------------------------------------------------------
//	PrintSVG_DefSubCell (fOut tempLibName libName subCell layerList defsList)
//
//  Outputs the list of subcells that has been processed (defsList).
//  Prints the subcell geometry to the defs block so it can be reused.
// 
//  fOut - handle to the SVG output file
//  tempLibName - name of the temporary directory used for processing
//  libName - name of the library for the original (topmost) cell
//  subCell - handle to the layout subcell to be defined
//  layerList - list of layers to draw produced by MakeLayerList(..)
//  defsList - list of subcells that have been processed to defs
//  
// ---------------------------------------------------------------------------------------- */
(defun PrintSVG_DefSubCell (fOut tempLibName libName subCell layerList defsList)
	(let (subCellOriginal subCellCopy)

		; Before processing, check that the current cell is not already in the list of defs
		(unless (member (strcat subCell~>libName subCell~>cellName subCell~>viewName) (car defsList))
			; For debug, print info about curent subCell to console
			(printf "Adding %s/%s/%s to defs\n" subCell~>libName subCell~>cellName subCell~>viewName)

			; Append curent subCell to the list of defs
			defsList = (tconc defsList (strcat subCell~>libName subCell~>cellName subCell~>viewName))

			; As with the top-level cell, copy the original into the temporary library for processing
			subCellOriginal = (dbOpenCellViewByType subCell~>libName subCell~>cellName subCell~>viewName "maskLayout" "r")
			subCellCopy = (dbCopyCellView subCellOriginal tempLibName (strcat subCell~>libName "-" subCell~>cellName) subCell~>viewName)
			(dbClose subCellOriginal)

			; Print the top-level subcell geometry to a symbol block in the defs
			(fprintf fOut "<symbol id=\"%s\">\n" (strcat subCellCopy~>cellName "-" subCellCopy~>viewName))
			(PrintSVG_ArtMaster fOut subCellCopy layerList 0 0)
			(fprintf fOut "</symbol>\n")

			; If necessary, continue down the hierarchy to the [sub]subcells within the current [sub]cell
			(foreach subSubCell subCellCopy~>instances
			   defsList = (PrintSVG_DefSubCell fOut tempLibName libName subSubCell layerList defsList))
			
			; Cleanup the copied subcell from the tempLib
	  		(ddDeleteObj (ddGetObj tempLibName (strcat subCell~>libName "-" subCell~>cellName)))
	  	)
	)
	defsList
)

/* ----------------------------------------------------------------------------------------
//	PrintSVG_ArtMaster (fOut cell layerList offX offY)
//
//  Outputs the list of subcells that has been processed (defsList).
//  Prints the subcell geometry to the defs block so it can be reused.
// 
//  fOut - handle to the SVG output file
//  cell - handle to the cell to be drawn
//  layerList - list of layers to draw produced by MakeLayerList(..)
//  offX - x-coordinate of lower left corner of topmost cell
//  offY - y-coordinate of lower left corner of topmost cell
//  
// ---------------------------------------------------------------------------------------- */
(defun PrintSVG_ArtMaster (fOut cell layerList offX offY)
	(let (pHeight)
		; Calculate the height of the parent cell
		pHeight = (yCoord (cadr cell~>bBox))*SCALE - (yCoord (car cell~>bBox))*SCALE + offY

		; Flatten the current top level (vias, pcells, mosaics, and any geometry created on top of subcells)
		(Flatten1L cell)

		; If necessary, print <use> statements to instantiate subcells that were defined in <defs>
		(foreach defCell cell~>instances 
			(if defCell~>objType == "inst" then
				(PrintSVG_ArtUse fOut defCell offX pHeight)
			)
		)

		; Following the order in *.layers, call appropriate functions to print geometry 
		(foreach layer layerList
			(foreach shape cell~>shapes
				(if (strcat shape~>layerName shape~>purpose) == layer then
					(cond
						(shape~>objType == "rect"
							(PrintSVG_ArtRectangle fOut shape offX pHeight)
						)
						(shape~>objType == "polygon"
							(PrintSVG_ArtPolygon fOut shape offX pHeight)
						)
						(shape~>objType == "path"
							(dbConvertPathToPolygon shape)
							(PrintSVG_ArtPolygon fOut shape offX pHeight)
						)
					)
				)
			)
		)
	)   
)

/* ----------------------------------------------------------------------------------------
//	PrintSVG_ArtPolygon (fOut shape offX pHeight)
//
//  Prints a polygon to the SVG file using the given shape
// 
//  fOut - handle to the SVG output file
//  shape - handle to the shape to be printed
//  offX - x-coordinate of lower left corner of parent
//  pHeight - height of the parent cell
//  
// ---------------------------------------------------------------------------------------- */
(defun PrintSVG_ArtPolygon (fOut shape offX pHeight)
    (let (points x y)
    	; Build polygon by iterating through the points in the shape
    	(fprintf fOut "<polygon class=\"%s%s\" points=\"" shape~>layerName shape~>purpose)
    	points = shape~>path
    	(foreach p points 
    		x = (xCoord p)*SCALE - offX
    		y = pHeight - (yCoord p)*SCALE
    		(fprintf fOut "%g,%g " x y)
    	)
    	(fprintf fOut "\"/>\n")
   	)
)

/* ----------------------------------------------------------------------------------------
//	PrintSVG_ArtRectangle (fOut shape offX pHeight)
//
//  Prints a rectangle to the SVG file using the given shape
// 
//  fOut - handle to the SVG output file
//  shape - handle to the shape to be printed
//  offX - x-coordinate of lower left corner of parent
//  pHeight - height of the parent cell
//  
// ---------------------------------------------------------------------------------------- */
(defun PrintSVG_ArtRectangle (fOut shape offX pHeight)
    (let (x1 y1 x2 y2)
    	; Rectangle is a simple case of the SVG polygon object
    	x1 = (xCoord (car shape~>bBox))*SCALE - offX
    	y1 = pHeight - (yCoord (car shape~>bBox))*SCALE
    	x2 = (xCoord (cadr shape~>bBox))*SCALE - offX
    	y2 = pHeight - (yCoord (cadr shape~>bBox))*SCALE

    	(fprintf fOut "<polygon class=\"%s%s\" points=\"%g,%g %g,%g %g,%g %g,%g %g,%g\"/>\n" 
    		shape~>layerName shape~>purpose x1 y1 x2 y1 x2 y2 x1 y2 x1 y1)
    )
)

/* ----------------------------------------------------------------------------------------
//	PrintSVG_ArtUse (fOut subCell offX pHeight)
//
//  Outputs the list of subcells that has been processed (defsList).
//  Prints the subcell geometry to the defs block so it can be reused.
// 
//  fOut - handle to the SVG output file
//  subCell - handle to the subCell to be drawn
//  offX - x-coordinate of lower left corner of top-level cell
//  pHeight - the height of the parent cell
//  
// ---------------------------------------------------------------------------------------- */
(defun PrintSVG_ArtUse (fOut subCell offX pHeight)
	(let (x y)
		; Correct coordinates based on offset and height
		x = (xCoord subCell~>xy)*SCALE - offX
		y = pHeight - (yCoord subCell~>xy)*SCALE

		; Flip coordinates if the shape has been mirrored
		(cond
			(subCell~>orient == "MY" || subCell~>orient == "MYR90" 
				x = -x
			)
			(subCell~> orient == "MX" || subCell~>orient == "MXR90"
				y = -y 
			)
		)

		; Fix coordinates based on mirroring/rotation
		(cond 
			(subCell~>orient == "R0" || subCell~>orient == "MX" || subCell~>orient == "MY"
				y = y - (abs (yCoord (cadr subCell~>bBox)) - (yCoord (car subCell~>bBox)))*SCALE
			)
			(subCell~>orient == "R90"
				x = x - (abs (xCoord (cadr subCell~>bBox)) - (xCoord (car subCell~>bBox)))*SCALE
			)
			(subCell~>orient == "R180" 
				y = y + (abs (yCoord (cadr subCell~>bBox)) - (yCoord (car subCell~>bBox)))*SCALE
			)
			(subCell~>orient == "R270" || subCell~>orient == "MXR90" || subCell~>orient == "MYR90"
				x = x + (abs (xCoord (cadr subCell~>bBox)) - (xCoord (car subCell~>bBox)))*SCALE
			)
		)

		; Setup <use> statement for the current subcell
		(fprintf fOut "<use x=\"%g\" y=\"%g\" xlink:href=\"#%s-%s-%s\" " x y subCell~>libName subCell~>cellName subCell~>viewName)

		; Add transformation/scaling data based on mirroring/rotation
		(cond
			(subCell~>orient == "R90"
				(fprintf fOut "transform=\"rotate(-90,%g,%g)\"" x y)
			)
			(subCell~>orient == "R180"
				(fprintf fOut "transform=\"rotate(-180,%g,%g)\"" x y)
			)
			(subCell~>orient == "R270"
				(fprintf fOut "transform=\"rotate(-270,%g,%g)\"" x y)
			)
			(subCell~>orient == "MY"
				(fprintf fOut "transform=\"scale(-1,1)\"")
			)
			(subCell~>orient == "MYR90"
				(fprintf fOut "transform=\"scale(-1,1) rotate(90,%g,%g)\"" x y)
			)
			(subCell~>orient == "MX"
				(fprintf fOut "transform=\"scale(1,-1)\"")
			)
			(subCell~>orient == "MXR90"
				(fprintf fOut "transform=\"scale(1,-1) rotate(90,%g,%g)\"" x y)
			)
		)
		(fprintf fOut "/>\n")
	)
)

/* ----------------------------------------------------------------------------------------
//	PrintSVG_Footer (fOut)
//
//	Simple function to compartmentalize the action of printing the footer of the SVG file.
//
//  fOut - handle to the SVG output file
//  
// ---------------------------------------------------------------------------------------- */
(defun PrintSVG_Footer (fOut)
    (fprintf fOut "</svg>\n")
)

