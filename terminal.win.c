#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

#define BUF_SIZE 2048

#define FUNC(ret, name, ...)				\
	typedef ret (*PFN_##name) (__VA_ARG__); \
	PFN_##name name = NULL;

#define IMPORT(name)								\
	name = (PFN_##name) GetProcAddress(lib, #name); \
	if (name == NULL) return GetLastError();


#define WINPTY_SPAWN_FLAG_AUTO_SHUTDOWN 1ull
#define WINPTY_SPAWN_FLAG_EXIT_AFTER_SHUTDOWN 2ull
#define WINPTY_SPAWN_FLAG_MASK (0ull \
    | WINPTY_SPAWN_FLAG_AUTO_SHUTDOWN \
    | WINPTY_SPAWN_FLAG_EXIT_AFTER_SHUTDOWN \
)

typedef struct winpty_error_s winpty_error_t;
typedef winpty_error_t *winpty_error_ptr_t;

typedef DWORD winpty_result_t;

FUNC(LPCWSTR, winpty_error_msg, winpty_error_ptr_t)
FUNC(void,    winpty_error_free, winpty_error_ptr_t)

typedef struct winpty_config_s winpty_config_t;
FUNC(winpty_config_t *, winpty_config_new, UINT64, winpty_error_ptr_t *)
FUNC(void, winpty_config_free, winpty_config_t *)
FUNC(void, winpty_config_set_initial_size, winpty_config_t *, int, int)
FUNC(void, winpty_config_set_mouse_mode, winpty_config_t *, int)
FUNC(void, winpty_config_set_agent_timeout, winpty_config_t *, DWORD)

typedef struct winpty_s winpty_t;
FUNC(winpty_t *, winpty_open, const winpty_config_t *, winpty_error_ptr_t *)

FUNC(LPCWSTR, winpty_conin_name, winpty_t *)
FUNC(LPCWSTR, winpty_conout_name, winpty_t *)

typedef struct winpty_spawn_config_s winpty_spawn_config_t;
FUNC(winpty_spawn_config_t *, winpty_spawn_config_new,  UINT64, LPCWSTR, LPCWSTR, LPCWSTR, LPCWSTR, winpty_error_ptr_t *)
FUNC(void, 					  winpty_spawn_config_free, winpty_spawn_config_t *)
FUNC(BOOL, 					  winpty_spawn,             winpty_t *, const winpty_spawn_config_t *, HANDLE *, HANDLE *, DWORD *, winpty_error_ptr_t *)
FUNC(void, 					  winpty_free,              winpty_t *)

static DWORD load_winpty() {
	HMODULE lib = LoadLibrary("winpty.dll");
	if (lib == NULL)
		return GetLastError();
	IMPORT(winpty_error_msg)
	IMPORT(winpty_error_free)
	IMPORT(winpty_config_new)
	IMPORT(winpty_config_free)
	IMPORT(winpty_config_set_initial_size)
	IMPORT(winpty_config_set_mouse_mode)
	IMPORT(winpty_config_set_agent_timeout)
	IMPORT(winpty_open)
	IMPORT(winpty_conin_name)
	IMPORT(winpty_conout_name)
	IMPORT(winpty_spawn_config_new)
	IMPORT(winpty_spawn_config_free)
	IMPORT(winpty_spawn)
	IMPORT(winpty_free)

	return ERROR_SUCCESS;
}

// because the proper function isn't defined by microsoft duh
uintptr_t _beginthreadex( // NATIVE CODE
   void *security,
   unsigned stack_size,
   unsigned ( __stdcall *start_address )( void * ),
   void *arglist,
   unsigned initflag,
   unsigned *thrdaddr
);


typedef struct {
	HANDLE read_side, write_side;
} pipe_pair_t;

__stdcall unsigned pipe_thread(void *ptr) {
	pipe_pair_t *pair = (pipe_pair_t *) ptr;

	char buf[BUF_SIZE];

	DWORD read = 0, write = 0;
	BOOL r = FALSE, w = FALSE;
	do {
		r = ReadFile(pair->read_side, buf, BUF_SIZE, &read, NULL);
		w = WriteFile(pair->write_side, buf, read, &write, NULL);
	} while (r && w && read >= 0 && w >= 0);
	return 0;
}

static void winpty_error(winpty_error_ptr_t err) {
	LPCWSTR msg = winpty_error_msg(err);
	fwprintf(stderr, L"winpty: %ls\n", msg);
	winpty_error_free(err);
}

static void win32_error(DWORD err) {
	LPWSTR msg = NULL;
	FormatMessageW(
		FORMAT_MESSAGE_ALLOCATE_BUFFER
		| FORMAT_MESSAGE_FROM_SYSTEM
		| FORMAT_MESSAGE_IGNORE_INSERTS,
		NULL,
		err,
		MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
		(LPWSTR) &msg,
		0,
		NULL
	);

	if (msg != NULL) {
		fwprintf(stderr, L"error: %ls\n", msg);
		LocalFree(msg);
	}
}

int main() {
	DWORD res = load_winpty();
	if (res != ERROR_SUCCESS) {
		win32_error(res);
		return 1;
	}

	int argc = 0;
	LPWSTR cmdline = GetCommandLineW();
	LPWSTR *argv = CommandLineToArgvW(cmdline, &argc);

	if (argc < 2) {
		fprintf(stderr, "error: insufficient arguments\n");
		return 1;
	}

	winpty_error_ptr_t err = NULL;
	winpty_config_t *config = NULL;
	winpty_t *pty = NULL;
	winpty_spawn_config_t *spawn_config = NULL;

	HANDLE stdin_handle, stdout_handle, pty_in, pty_out;
	HANDLE threads[2];

	config = winpty_config_new(0, &err);
	if (config == NULL) {
		winpty_error(err);
		goto cleanup;
	}
	winpty_error_free(err);

	winpty_config_set_initial_size(config, 80, 24);
	
	pty = winpty_open(config, &err);
	if (pty == NULL) {
		winpty_error(err);
		goto cleanup;
	}
	winpty_error_free(err);

	LPCWSTR pty_in_name = winpty_conin_name(pty);
	LPCWSTR pty_out_name = winpty_conout_name(pty);

	stdin_handle = GetStdHandle(STD_INPUT_HANDLE);
	stdout_handle = GetStdHandle(STD_OUTPUT_HANDLE);

	pty_in = CreateFileW(pty_in_name, GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
	pty_out = CreateFileW(pty_out_name, GENERIC_READ, 0, NULL, OPEN_EXISTING, 0, NULL);

	if (pty_in == INVALID_HANDLE_VALUE || pty_out == INVALID_HANDLE_VALUE) {
		win32_error(GetLastError());
		goto cleanup;
	}

	pipe_pair_t read_pair = {
		stdin_handle,
		pty_in
	};

	pipe_pair_t write_pair = {
		pty_out,
		stdout_handle
	};

	unsigned thread_id;
	threads[0] = (HANDLE) _beginthreadex(NULL, 0, pipe_thread, &read_pair, 0, &thread_id);
	threads[1] = (HANDLE) _beginthreadex(NULL, 0, pipe_thread, &write_pair, 0, &thread_id);

	spawn_config = winpty_spawn_config_new(WINPTY_SPAWN_FLAG_MASK, argv[1], NULL, NULL, NULL, &err);
	if (spawn_config == NULL) {
		winpty_error(err);
		goto cleanup;
	}
	winpty_error_free(err);

	if (!winpty_spawn(pty, spawn_config, NULL, NULL, NULL, &err)) {
		winpty_error(err);
		goto cleanup;
	}
	winpty_error_free(err);

	WaitForMultipleObjects(2, threads, FALSE, INFINITE);

cleanup:
	winpty_config_free(config);
	winpty_free(pty);
	winpty_spawn_config_free(spawn_config);
	CloseHandle(threads[0]);
	CloseHandle(threads[1]);
	CloseHandle(pty_in);
	CloseHandle(pty_out);

	return 0;
}