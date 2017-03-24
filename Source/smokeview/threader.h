#ifndef THREADER_H_DEFINED
#define THREADER_H_DEFINED
#ifndef CPP
#ifdef pp_THREAD
#include <pthread.h>
#endif
#endif

#ifdef INTHREADER
#define MT_EXTERN
#else
#define MT_EXTERN extern CCC
#endif

// setup LOCKS

#ifdef pp_THREAD
  #define LOCK_COMPRESS     pthread_mutex_lock(&mutexCOMPRESS);
  #define UNLOCK_COMPRESS   pthread_mutex_unlock(&mutexCOMPRESS);
  #define LOCK_VOLLOAD      pthread_mutex_lock(&mutexVOLLOAD);
  #define UNLOCK_VOLLOAD    pthread_mutex_unlock(&mutexVOLLOAD);
  #define LOCK_BUILDSLICE   pthread_mutex_lock(&mutexBUILDSLICE);
  #define UNLOCK_BUILDSLICE pthread_mutex_unlock(&mutexBUILDSLICE);
  #define JOIN_BUILDSLICE   pthread_join(buildslice_id,NULL);
#ifdef pp_THREADIBLANK
  #define LOCK_IBLANK       pthread_mutex_lock(&mutexIBLANK);
  #define UNLOCK_IBLANK     pthread_mutex_unlock(&mutexIBLANK);
  #define JOIN_IBLANK       pthread_join(makeiblank_thread_id,NULL);
#else
  #define LOCK_IBLANK
  #define UNLOCK_IBLANK
  #define JOIN_IBLANK
#endif
#else
  #define LOCK_COMPRESS
  #define UNLOCK_COMPRESS
  #define LOCK_VOLLOAD
  #define UNLOCK_VOLLOAD
  #define LOCK_IBLANK
  #define UNLOCK_IBLANK
  #define JOIN_IBLANK
  #define LOCK_BUILDSLICE
  #define UNLOCK_BUILDSLICE
  #define JOIN_BUILDSLICE
#endif

#ifdef pp_THREAD
void mt_ReadVolsmokeAllFramesAllMeshes2(void);
#ifdef pp_SLICETHREAD
void mt_UpdateVSlices(void);
#endif
#endif

// define mutex's and thread_ids

#ifndef CPP
#ifdef pp_THREAD
MT_EXTERN pthread_t makeiblank_thread_id;
MT_EXTERN pthread_mutex_t mutexIBLANK;
MT_EXTERN pthread_mutex_t mutexBUILDSLICE;
MT_EXTERN pthread_mutex_t mutexVOLLOAD;
MT_EXTERN pthread_mutex_t mutexCOMPRESS;
MT_EXTERN pthread_t system_thread_id;
MT_EXTERN pthread_t compress_thread_id;
MT_EXTERN pthread_t update_all_patch_bounds_id;
MT_EXTERN pthread_t read_volsmoke_id;
MT_EXTERN pthread_t buildslice_id;
#endif
#endif
#endif

