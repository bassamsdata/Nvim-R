# R may break strings while sending them even if they are short
out <- function(x) {
    # Nvim-R will wait for more input if the string doesn't end with "\002"
    y <- paste0(x, "\002\n")
    cat(y)
    flush(stdout())
}

isdir <- file.info(Sys.getenv("NVIMR_TMPDIR"))[["isdir"]]
if (is.na(isdir)) {
    out(paste0("RWarn: R: NVIMR_TMPDIR (`", Sys.getenv("NVIMR_TMPDIR"), "`) not found."))
} else {
    if (!isdir)
        out(paste0("RWarn: R: NVIMR_TMPDIR (`", Sys.getenv("NVIMR_TMPDIR"), "`) is not a directory."))
}

isdir <- file.info(Sys.getenv("NVIMR_COMPLDIR"))[["isdir"]]
if (is.na(isdir)) {
    out(paste0("RWarn: R: NVIMR_COMPLDIR (`", Sys.getenv("NVIMR_COMPLDIR"), "`) not found."))
} else {
    if (!isdir)
        out(paste0("RWarn: R: NVIMR_COMPLDIR (`", Sys.getenv("NVIMR_COMPLDIR"), "`) is not a directory."))
}

setwd(Sys.getenv("NVIMR_TMPDIR"))

# Save libPaths for nclientserver
libp <- unique(c(unlist(strsplit(Sys.getenv("R_LIBS_USER"),
                                 .Platform$path.sep)), .libPaths()))
cat(libp, sep = "\n", colapse = "\n", file = "libPaths")

# Check R version
R_version <- paste0(version[c("major", "minor")], collapse = ".")

if (R_version < "4.0.0")
    out("RWarn: Nvim-R requires R >= 4.0.0")

R_version <- sub("[0-9]$", "", R_version)

need_new_nvimcom <- ""

# The nvimcom directory will not exist if nvimcom was packaged separately from
# the rest of Nvim-R. I will also not be found if running Vim in MSYS2 and R
# on Windows because the directory names change between the two systems.
if (file.exists(paste0(nvim_r_home, "/R/nvimcom/DESCRIPTION"))) {
    # Check nvimcom version.
    nd <- readLines(paste0(nvim_r_home, "/R/nvimcom/DESCRIPTION"))
    nd <- nd[grepl("Version:", nd)]
    needed_nvc_version <- sub("Version: ", "", nd)

    ip <- utils::installed.packages()
    if (length(grep("^nvimcom$", rownames(ip))) == 1) {
        nvimcom_info <- ip["nvimcom", c("Version", "LibPath", "Built")]
        if (!grepl(paste0('^', R_version), nvimcom_info["Built"])) {
            need_new_nvimcom <- "R version mismatch"
        } else {
            if (nvimcom_info["Version"] != needed_nvc_version) {
                need_new_nvimcom <- "nvimcom version mismatch"
                fi <- file.info(paste0(nvimcom_info["LibPath"], "/nvimcom/DESCRIPTION"))
                if (sum(grepl("uname", names(fi))) == 1 &&
                    Sys.getenv("USER") != "" &&
                    Sys.getenv("USER") != fi[["uname"]]) {
                    need_new_nvimcom <-
                        paste0(need_new_nvimcom, " (nvimcom ", nvimcom_info[["Version"]],
                               " was installed in `", nvimcom_info[["LibPath"]], "` by \"", fi[["uname"]], "\")")
                }
            }
        }
    } else {
        if (length(grep("^nvimcom$", rownames(ip))) == 0)
            need_new_nvimcom <- "Nvimcom not installed"
    }

    # Build and install nvimcom if necessary
    if (need_new_nvimcom != "") {
        out(paste0("let g:rplugin.debug_info['Why build nvimcom'] = '", need_new_nvimcom, "'"))

        # Check if any directory in libPaths is writable
        ok <- FALSE
        for (p in libp)
            if (dir.exists(p) && file.access(p, mode = 2) == 0)
                ok <- TRUE
        if (!ok) {
            out(paste0("let s:libd = '", libp[1], "'"))
            quit(save = "no", status = 71)
        }

        if (!ok) {
            out("RWarn: No suitable directory found to install nvimcom")
            quit(save = "no")
        }

        out("echo \"Building nvimcom... \"")
        tools:::.build_packages(paste0(nvim_r_home, "/R/nvimcom"), no.q = TRUE)
        if (!file.exists(paste0("nvimcom_", needed_nvc_version, ".tar.gz"))) {
            out("RWarn: Failed to build nvimcom.")
            quit(save = "no")
        }

        out("echo \"Installing nvimcom... \"")
        tools:::.install_packages(paste0("nvimcom_", needed_nvc_version, ".tar.gz"), no.q = TRUE)
        unlink(paste0("nvimcom_", needed_nvc_version, ".tar.gz"))
        ip <- utils::installed.packages()
        if (length(grep("^nvimcom$", rownames(ip))) == 0) {
            if (dir.exists(paste0(libp[1], "/00LOCK-nvimcom")))
                out(paste0('RWarn: Failed to install nvimcom. Perhaps you should delete the directory "', libp[1], '/00LOCK-nvimcom"'))
            else
                out("RWarn: Failed to install nvimcom.")
            quit(save = "no")
        }
        if (length(grep("^nvimcom$", rownames(ip))) > 1) {
            out("RWarn: More than one nvimcom versions installed.")
            quit(save = "no")
        }
        nvimcom_version <- ip["nvimcom", "Version"]
        if (nvimcom_version != needed_nvc_version) {
            out("RWarn: Failed to update nvimcom.")
            quit(save = "no")
        }
    }
}

# Save ~/.cache/Nvim-R/nvimcom_info
ip <- utils::installed.packages()
if (length(grep("^nvimcom$", rownames(ip))) == 1) {
    nvimcom_info <- unname(ip["nvimcom", c("Version", "LibPath", "Built")])
    writeLines(nvimcom_info, paste0(Sys.getenv("NVIMR_COMPLDIR"), "/nvimcom_info"))

    # Build omnils_, fun_ and args_ files, if necessary
    library("nvimcom")
    libs <- libs[libs %in% rownames(ip)]
    cat(paste(libs, utils::installed.packages()[libs, 'Version'], collapse = '\n', sep = '_'),
        '\n', sep = '', file = paste0(Sys.getenv("NVIMR_TMPDIR"), "/libnames_", Sys.getenv("NVIMR_ID")))
    nvimcom:::nvim.buildomnils(libs)
    out("echo ''")
    quit(save = "no")
}

if (length(grep("^nvimcom$", rownames(ip))) == 0) {
    out("RWarn: nvimcom is not installed.")
    for (p in libp)
        if (dir.exists(paste0(p, "/00LOCK-nvimcom")))
            out(paste0('RWarn: nvimcom is not installed. Perhaps you should delete the directory "', p, '/00LOCK-nvimcom"'))
    quit(save = "no")
}

if (length(grep("^nvimcom$", rownames(ip))) > 1) {
    out(paste0("RWarn: nvimcom is installed in more than one directory: ",
               paste0(ip[grep("^nvimcom$", rownames(ip)), "LibPath"], collapse = ", ")))
    quit(save = "no")
}
