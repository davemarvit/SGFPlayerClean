#pragma once
#ifdef __cplusplus
extern "C" {
#endif
// Serialized calls except QKGCancel, which may be called from any thread.
char *QKGAnalyze(const char *modelPath, const char *requestJSON);
void QKGPrepare(void);
void QKGCancel(void);
void QKGFree(char *result);
void QKGUnload(void);
#ifdef __cplusplus
}
#endif
