/*
** test_exec.c
** 
** Made by (Benjamin Negrevergne)
** Email   <Benjamin.Negrevergne[at]imag[dot]fr>
** 
** Started on  Sat Mar 10 19:51:51 2012 Benjamin Negrevergne
*/


/* Test program fakes a computation, the first parameter is the number
   of iterations, the second is a number of threads.
   The more iteration the longer, the more threads the shorter. 



compile: 
 gcc test_exec.c -o test_exec -l pthread
 
 exec: 
./test_exec 5000 1    # will take about 10 sec
./test_exec 5000 4    # will take about 2.5 sec (assuming 4 processors/cores)
./test_exec 10000 4   # will take about 5 sec (assuming 4 processors/cores)

  */

#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <unistd.h>

int num_threads; 
int num_iter= 1000;
void *thread_func(void *a){
  int i; 
  
  for(i = 0; i < num_iter/num_threads; i++){
    usleep(1000); 
  }
}

int main(int argc, char **argv){
  if(argc != 3){
    fprintf(stderr, "Usage: %s num_iter, num_threads\n", argv[0]);
    return EXIT_FAILURE; 
  }

  num_iter = atoi(argv[1]);
  num_threads = atoi(argv[2]);
  int i;
  
  pthread_t *tids = malloc(sizeof(pthread_t) * num_threads);
  
  for(i = 0; i < num_threads; i++){
    pthread_create(&tids[i], NULL, thread_func, NULL) ;
  }


  for(i = 0; i < num_threads; i++){
    pthread_join(tids[i], NULL);
  }


  free(tids); 

  return EXIT_SUCCESS; 
}
