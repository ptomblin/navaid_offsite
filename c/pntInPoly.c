/**
 * Read a shape file / database file into memory representing
 * provinces/territories.  Then read latitude/longitude pairs, and
 * determine which province the given latitude/longitude pair is in using
 * a point in polygon algorithm.
 * 
 * PnPoly is taken from W.Randolf Franklin's page
 * http://www.ecse.rpi.edu/Homepages/wrf/Research/Short_Notes/pnpoly.html
 *
 * The License for PnPoly is:
 * Copyright (c) 1970-2003, Wm. Randolph Franklin
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 *    1. Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimers.
 *    2. Redistributions in binary form must reproduce the above
 *       copyright notice in the documentation and/or other materials
 *       provided with the distribution.
 *    3. The name of W. Randolph Franklin may not be used to endorse
 *       or promote products derived from this Software without
 *       specific prior written permission. 
 *
 *    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 *    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *    NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 *    BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 *    ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 *    CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 *    SOFTWARE. 
 */

#include <stdio.h>
#include <malloc.h>
#include <stdlib.h>
#include <shapefil.h>
#include <string.h>

int pnpoly(int npol, double *xp, double *yp, double x, double y)
{
  int i, j, c = 0;
  for (i = 0, j = npol-1; i < npol; j = i++) {
	if ((((yp[i]<=y) && (y<yp[j])) ||
		 ((yp[j]<=y) && (y<yp[i]))) &&
		(x < (xp[j] - xp[i]) * (y - yp[i]) / (yp[j] - yp[i]) + xp[i]))

	  c = !c;
  }
  return c;
}

typedef struct
{
  int numPoints;
  char prov[2];

  double  minX;
  double  maxX;
  double  minY;
  double  maxY;

  double* xp;
  double* yp;
} Vertices;

typedef struct
{
  char* longName;
  char shortName[2];
} ProvinceNames;

ProvinceNames provinces[] = 
{
  {"Alberta", "AB"},
  {"British Columbia", "BC"},
  {"Manitoba", "MB"},
  {"New Brunswick", "NB"},
  {"Newfoundland", "NF"},
  {"Northwest Territories", "NT"},
  {"Nova Scotia", "NS"},
  {"Nunavut", "NU"},
  {"Ontario", "ON"},
  {"Prince Edward Island", "PE"},
  {"Quebec", "QC"},
  {"Saskatchewan", "SK"},
  {"Yukon Territory", "YT"}
};

void lookupProvince(const char* longName, char* shortName)
{
  int i;
  int numProv = sizeof(provinces)/sizeof(ProvinceNames);
  for (i = 0; i < numProv; i++)
  {
	if (strcmp(longName, provinces[i].longName) == 0)
	{
	  shortName[0] = provinces[i].shortName[0];
	  shortName[1] = provinces[i].shortName[1];
	  return;
	}
  }
  printf("no match found for [%s]\n", longName);
  exit(1);
}

int main(int argc, char* argv[])
{
  int i;
  char* fn = argv[1];

  Vertices* vertices;

  SHPHandle hSHP = SHPOpen(fn, "rb");
  DBFHandle hDBF = DBFOpen(fn, "rb");
  
  int pnEntities;
  int pnShapeType;
  double padfMinBound[4];
  double padfMaxBound[4];

  SHPGetInfo(hSHP, &pnEntities, &pnShapeType, padfMinBound, padfMaxBound);

  /*printf("num Entities = %d, shape type = %d, bounds = (%lf, %lf) - (%lf, %lf)\n",
	  pnEntities, pnShapeType, padfMinBound[0], padfMinBound[1],
	  padfMaxBound[0], padfMaxBound[1]);*/


  int numRecords = DBFGetRecordCount(hDBF);
  /*printf("numFields = %d, numRecords = %d\n", numFields, numRecords);*/
  if (numRecords != pnEntities)
  {
	printf("WHAT THE FUCK!!!\n");
	exit(2);
  }

  vertices = malloc(sizeof(Vertices) * pnEntities);

  for (i = 0; i < pnEntities; i++)
  {
	SHPObject *shape = SHPReadObject(hSHP, i);
	const char* longProvince = DBFReadStringAttribute(hDBF, i, 1);

	vertices[i].minX = shape->dfXMin;
	vertices[i].minY = shape->dfYMin;
	vertices[i].maxX = shape->dfXMax;
	vertices[i].maxY = shape->dfYMax;

	lookupProvince(longProvince, vertices[i].prov);
	/*printf("object %d, type = %d, nParts = %d, numVertices = %d, province = %s (%c%c)\n",
		i, shape->nSHPType, shape->nParts, shape->nVertices, longProvince,
		vertices[i].prov[0], vertices[i].prov[1]); */

	SHPRewindObject(hSHP, shape);

	int numV = shape->nParts + shape->nVertices + 1; // can't hurt to have a few extra
	vertices[i].xp = malloc(sizeof(double) * numV);
	vertices[i].yp = malloc(sizeof(double) * numV);

	int j, k = 0;
	int iPart = 1;

	if (shape->nParts > 1)
	{
	  vertices[i].xp[k] = 0.0;
	  vertices[i].yp[k] = 0.0;
	  k++;
	}

	for (j = 0; j < shape->nVertices; j++)
	{
	  if (iPart < shape->nParts &&
		  shape->panPartStart[iPart] == j)
	  {
		vertices[i].xp[k] = 0.0;
		vertices[i].yp[k] = 0.0;
		iPart++;
		k++;
	  }
	  vertices[i].xp[k] = shape->padfX[j];
	  vertices[i].yp[k] = shape->padfY[j];
	  k++;
	}

	if (shape->nParts > 1)
	{
	  vertices[i].xp[k] = 0.0;
	  vertices[i].yp[k] = 0.0;
	  k++;
	}
	vertices[i].numPoints = k;
	SHPDestroyObject(shape);
  }
  SHPClose(hSHP);
  DBFClose(hDBF);

  double lat, lon;
  while (1)
  {
	scanf("%lf %lf", &lat, &lon);
	if (lat < -998.0 || lat > 998.0)
	{
	  exit(0);
	}
#ifdef DEBUG
	printf("lat = %lf, lon = %lf\n", lat, lon);
#endif
	int shapeNum = 0;
	int foundVertex = -1;
	for (shapeNum = 0; shapeNum < pnEntities; shapeNum++)
	{
#ifdef DEBUG
	  printf("shapeNum[%d] (%lf, %lf) - (%lf,%lf) ", shapeNum,
		  vertices[shapeNum].minX, vertices[shapeNum].minY,
		  vertices[shapeNum].maxX, vertices[shapeNum].maxY);
#endif
	  if (vertices[shapeNum].minX <= lon &&
		  vertices[shapeNum].minY <= lat &&
		  vertices[shapeNum].maxX >= lon &&
		  vertices[shapeNum].maxY >= lat)
	  {
#ifdef DEBUG
		printf("testing\n");
#endif
		if (pnpoly(vertices[shapeNum].numPoints, vertices[shapeNum].xp, vertices[shapeNum].yp,
			  lon, lat))
		{
		  printf("%c%c", vertices[shapeNum].prov[0], vertices[shapeNum].prov[1]);
		  foundVertex = shapeNum;
		}
	  }
#ifdef DEBUG
	  else
	  {
		printf("skipping\n");
	  }
#endif
	}
#ifdef DEBUG
	if (foundVertex < 0)
	{
	  printf("no match found\n");
	}
#endif
	printf("\n");fflush(stdout);
  }
}
