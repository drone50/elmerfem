#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>

#include "nrutil.h"

#define NR_END 1
#define FREE_ARG char*


void nrerror(char error_text[])
/* Numerical Recipes standerd error handler */
{
  fprintf(stderr,"Numerical Recipes run-time error...\n");
  fprintf(stderr,"%s\n",error_text);
  fprintf(stderr,"...now exiting to system...\n");
  exit(1);
}


/******************* VEKTORIEN INITIALISOINTI **********************/

float *vector(int nl,int nh)
/* allocate a float vector with subscript range v[nl..nh] */
{
  float *v;

  v = (float*)malloc((size_t) (nh-nl+1+NR_END)*sizeof(float));
  if (!v) nrerror("allocation failure in vector()");
  return(v-nl+NR_END);
}



int *ivector(int nl,int nh)
/* Allocate an int vector with subscript range v[nl..nh] */
{
  int *v;
  
  v=(int*) malloc((size_t) (nh-nl+1+NR_END)*sizeof(int));
  if (!v) nrerror("allocation failure in ivector()");
  return(v-nl+NR_END);
}


unsigned char *cvector(int nl,int nh)
/* allocate an unsigned char vector with subscript range v[nl..nh] */
{
  unsigned char *v;
  
  v=(unsigned char *)malloc((size_t) (nh-nl+1+NR_END)*sizeof(unsigned char));
  if (!v) nrerror("allocation failure in cvector()");
  return(v-nl+NR_END);
}


unsigned long *lvector(int nl,int nh)
/* allocate an unsigned long vector with subscript range v[nl..nh] */
{
  unsigned long *v;
  
  v=(unsigned long *)malloc((size_t) (nh-nl+1+NR_END)*sizeof(unsigned long));
  if (!v) nrerror("allocation failure in lvector()");
  return(v-nl+NR_END);
}



double *dvector(int nl,int nh)
/* allocate a double vector with subscript range v[nl..nh] */
{
  double *v;
  
  v=(double *)malloc((size_t) (nh-nl+1+NR_END)*sizeof(double));
  if (!v) nrerror("allocation failure in dvector()");
  return(v-nl+NR_END);
}


/******************* MATRIISIEN INITIALISOINTI **********************/

float **matrix(int nrl,int nrh,int ncl,int nch)
/* allocate a float matrix with subscript range m[nrl..nrh][ncl..nch] */
{
  int i, nrow=nrh-nrl+1, ncol=nch-ncl+1;
  float **m;
  
  /* allocate pointers to rows */
  m=(float **) malloc((size_t) (nrow+NR_END)*sizeof(float*));
  if (!m) nrerror("allocation failure 1 in matrix()");
  m += NR_END;
  m -= nrl;
  
  /* allocate rows and set pointers to them */
  m[nrl]=(float *) malloc((size_t)((nrow*ncol+NR_END)*sizeof(float)));
  if (!m[nrl]) nrerror("allocation failure 2 in matrix()");
  m[nrl] += NR_END;
  m[nrl] -= ncl;
  
  for(i=nrl+1;i<=nrh;i++)
    m[i]=m[i-1]+ncol;
  
  return(m);
}


double **dmatrix(int nrl,int nrh,int ncl,int nch)
/* allocate a double matrix with subscript range m[nrl..nrh][ncl..nch] */
{
  int i, nrow=nrh-nrl+1, ncol=nch-ncl+1;
  double **m;
  
  /* allocate pointers to rows */
  m=(double **) malloc((size_t) (nrow+NR_END)*sizeof(double*));
  if (!m) nrerror("allocation failure 1 in dmatrix()");
  m += NR_END;
  m -= nrl;
  
  /* allocate rows and set pointers to them */
  m[nrl]=(double *) malloc((size_t)((nrow*ncol+NR_END)*sizeof(double)));
  if (!m[nrl]) nrerror("allocation failure 2 in dmatrix()");
  m[nrl] += NR_END;
  m[nrl] -= ncl;
  
  for(i=nrl+1;i<=nrh;i++)
    m[i]=m[i-1]+ncol;
  
  return(m);
} 


int **imatrix(int nrl,int nrh,int ncl,int nch)
/* allocate an int matrix with subscript range m[nrl..nrh][ncl..nch] */
{
  int i, nrow=nrh-nrl+1, ncol=nch-ncl+1;
  int **m;
  
  /* allocate pointers to rows */
  m=(int **) malloc((size_t) (nrow+NR_END)*sizeof(int*));
  if (!m) nrerror("allocation failure 1 in imatrix()");
  m += NR_END;
  m -= nrl;
  
  /* allocate rows and set pointers to them */
  m[nrl]=(int *) malloc((size_t)((nrow*ncol+NR_END)*sizeof(int)));
  if (!m[nrl]) nrerror("allocation failure 2 in imatrix()");
  m[nrl] += NR_END;
  m[nrl] -= ncl;
  
  for(i=nrl+1;i<=nrh;i++)
    m[i]=m[i-1]+ncol;
  
  return(m);
} 



float **submatrix(float **a,int oldrl,int oldrh,int oldcl,int oldch,int newrl,int newcl)
/* point a submatrix [newrl..][newcl..] to a[oldrl..oldrh][oldcl..oldch] */
{
  int i,j, nrow=oldrh-oldrl+1, ncol=oldcl-newcl;
  float **m;
  
  /* allocate array of pointers to rows */
  m=(float **) malloc((size_t) ((nrow+NR_END)*sizeof(float*)));
  if (!m) nrerror("allocation failure in submatrix()");
  m += NR_END;
  m -= newrl;
  
  /* set pointers to rows */
  for(i=oldrl,j=newrl;i<=oldrh;i++,j++) 
    m[j]=a[i]+ncol;
  
  return(m);
}

/******************* TENSORIEN INITIALISOINTI **********************/

double ***f3tensor(int nrl,int nrh,int ncl,int nch,int ndl,int ndh)
/* allocate a double 3tensor with range t[nrl..nrh][ncl..nch][ndl..ndh] */
{
  int i,j,nrow=nrh-nrl+1,ncol=nch-ncl+1,ndep=ndh-ndl+1;
  double ***t;

  t=(double***) malloc((size_t)((nrow+NR_END)*sizeof(double***)));
  if (!t) nrerror("allocation failure 1 in f3tensor()");
  t += NR_END;
  t -= nrl;

  t[nrl]=(double**) malloc((size_t)((nrow*ncol+NR_END)*sizeof(double*)));
  if(!t[nrl]) nrerror("allocation failure 2 in f3tensor()");
  t[nrl] += NR_END;
  t[nrl] -= ncl;

  t[nrl][ncl]=(double*) malloc((size_t)((nrow*ncol*ndep+NR_END)*sizeof(double)));
  if(!t[nrl][ncl]) nrerror("allocation failure 3 in f3tensor()");
  t[nrl][ncl] += NR_END;
  t[nrl][ncl] -= ndl;

  for(j=ncl+1;j<=nch;j++) t[nrl][j] = t[nrl][j-1]+ndep;
  for(i=nrl+1;i<=nrh;i++) {
    t[i] = t[i-1]+ncol;
    t[i][ncl] = t[i-1][ncl]+ncol*ndep;
    for(j=ncl+1;j<=nch;j++) t[i][j] = t[i][j-1]+ndep;
  }
  return(t);
}


/******************* VEKTOREIDEN VAPAUTTAMINEN **********************/


void free_vector(float *v,int nl,int nh)
{
  free((FREE_ARG) (v+nl-NR_END));
}


void free_ivector(int *v,int nl,int nh)
{
  free((FREE_ARG) (v+nl-NR_END));
}

void free_cvector(unsigned char *v,int nl,int nh)
{
  free((FREE_ARG) (v+nl-NR_END));
}


void free_lvector(unsigned long *v,int nl,int nh)
{
  free((FREE_ARG) (v+nl-NR_END));
}


void free_dvector(double *v,int nl,int nh)
{
  free((FREE_ARG) (v+nl-NR_END));
}



/******************* MATRIISIEN VAPAUTTAMINEN **********************/


void free_matrix(float **m,int nrl,int nrh,int ncl,int nch)
{
  free((FREE_ARG) (m[nrl]+ncl-NR_END));
  free((FREE_ARG) (m+nrl-NR_END));
}


void free_dmatrix(double **m,int nrl,int nrh,int ncl,int nch)
{
  free((FREE_ARG) (m[nrl]+ncl-NR_END));
  free((FREE_ARG) (m+nrl-NR_END));
}


void free_imatrix(int **m,int nrl,int nrh,int ncl,int nch)
{
  free((FREE_ARG) (m[nrl]+ncl-NR_END));
  free((FREE_ARG) (m+nrl-NR_END));
}



void free_submatrix(float **b,int nrl,int nrh,int ncl,int nch)
{
  free((FREE_ARG) (b+nrl-NR_END));
}


/******************* TENSORIEN VAPAUTTAMINEN **********************/
void free_f3tensor(double ***t,int nrl,int nrh,int ncl,int nch,int ndl,int ndh)
{
  free((FREE_ARG) (t[nrl][ncl]+ndl-NR_END));
  free((FREE_ARG) (t[nrl]+ncl-NR_END));
  free((FREE_ARG) (t+nrl-NR_END));
}














