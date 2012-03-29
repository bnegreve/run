/*
** use_mem.c
** 
** Made by (Benjamin Negrevergne)
** Email   <Benjamin.Negrevergne[at]imag[dot]fr>
** 
** Started on  Thu Mar 29 15:07:14 2012 Benjamin Negrevergne
*/

#include <stdio.h>
#include <stdlib.h>

#define MAX_MEM 1024 // in MiB

int main(int argc, char **argv){
  if(argc != 3){
    fprintf(stderr, "%s <how much mem in mb> <for how long in s>\n", argv[0]); 
    return EXIT_FAILURE; 
  }
  size_t how_much = atoi(argv[1]);
  how_much = how_much>MAX_MEM?MAX_MEM:how_much;
  how_much<<= 20; //convert to bytes

  size_t how_long = atoi(argv[2]);

  char *q, *p = malloc(how_much); 
  
  for(q = p; q != p+how_much; q++){
    *q = (char)rand(); 
  }
  
  sleep(how_long); 

  return EXIT_SUCCESS; 
}
