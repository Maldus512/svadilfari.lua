#include <unistd.h>
#include <assert.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <errno.h>
#include <dirent.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>


static int find_with_extension(lua_State *L, const char *path, const char *extension, uint8_t recursive, size_t start);
static int l_find(lua_State *L);
static int l_execvp(lua_State *L);
static int l_mkdir(lua_State *L);
static int l_fullclean(lua_State *L);


static const struct luaL_Reg svadilfari_utils[] = {
    {"find", l_find}, {"execvp", l_execvp}, {"mkdir", l_mkdir}, {"fullclean", l_fullclean}, {NULL, NULL},
};


int luaopen_svadilfari_utils(lua_State *L) {
    luaL_newlib(L, svadilfari_utils);
    return 1;
}


static int find_with_extension(lua_State *L, const char *path, const char *extension, uint8_t recursive, size_t start) {
    DIR *dir = opendir(path);

    if (dir == NULL) {
        return 0;
    }
    struct dirent *entry = NULL;

    while ((entry = readdir(dir)) != NULL) { /* for each entry */
        struct stat s = {0};

        char file[PATH_MAX + 1] = {0};
        snprintf(file, sizeof(file), "%s/%s", path, entry->d_name);

        stat(file, &s);

        // It's a directory
        if ((s.st_mode & S_IFDIR) > 0 && strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0 &&
            recursive) {
            start = find_with_extension(L, file, extension, recursive, start);
        }
        // It's a file
        else if (s.st_mode & S_IFREG) {
            const char *filename_extension = strrchr(entry->d_name, '.');

            if ((extension == NULL) || (filename_extension != NULL && strcmp(&filename_extension[1], extension) == 0)) {
                lua_pushinteger(L, start++); /* push key */
                lua_pushstring(L, file);     /* push value */
                lua_settable(L, -3);
                /* table[i] = entry name */
            }
        }
    }
    closedir(dir);
    return start;
}


static const char *get_string_field(lua_State *L, const char *key) {
    lua_getfield(L, -1, key);
    const char *result = lua_tolstring(L, -1, NULL);
    lua_pop(L, 1);
    return result;
}


static uint8_t get_bool_field(lua_State *L, const char *key) {
    int result, isnum;
    lua_getfield(L, -1, key);
    uint8_t bool = lua_isboolean(L, -1) && lua_toboolean(L, -1);
    lua_pop(L, 1);
    return bool;
}


static int l_find(lua_State *L) {
    if (!lua_istable(L, 1)) {
        return 0;
    }

    uint8_t     recursive = get_bool_field(L, "recursive");
    const char *path      = get_string_field(L, "path");
    const char *extension = get_string_field(L, "extension");

    /* create result table */
    lua_newtable(L);
    find_with_extension(L, path, extension, recursive, 1);
    return 1; /* table is already on top */
}


static int l_execvp(lua_State *L) {
    size_t arguments_num = lua_gettop(L);
    if (arguments_num == 0) {
        return 0;
    }

    const char **argv = malloc((arguments_num + 1) * sizeof(char *));
    assert(argv);

    const char *executable = luaL_checkstring(L, 1);

    for (size_t i = 0; i < arguments_num; i++) {
        argv[i] = luaL_checkstring(L, i + 1);
    }
    argv[arguments_num] = NULL;

    execvp(executable, (char *const *)argv);
    perror("execvp failed");
    return 0;
}


static int l_mkdir(lua_State *L) {
    mkdir(luaL_checkstring(L, 1), 0755);
    return 0;
}


static int l_fullclean(lua_State *L) {
    if (!lua_istable(L, 1)) {
        return 0;
    }

    const char *output      = get_string_field(L, "output");
    const char *buildFolder = get_string_field(L, "buildFolder");

    int res = fork();
    if (res < 0) {
        perror("Fork failed");
    } else if (res == 0) {
        execlp("ninja", "ninja", "-f", output, "-t", "clean", NULL);
    } else {
        wait(NULL);
        if (buildFolder) {
            rmdir(buildFolder);
        }
        remove(output);
    }

    return 0;
}
