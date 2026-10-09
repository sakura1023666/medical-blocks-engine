#!/usr/bin/env Rscript
# 15_hearing_loss：修正 CHARLS 原始标签小节；去掉 NHANES 表权重行；同步到 UHR - 副本
suppressPackageStartupMessages(options(stringsAsFactors = FALSE, cli.hyperlink = FALSE, warn = 1))

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
study <- "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
cfg_path <- file.path(study, "config_incidence_dual_batch.R")
ix <- "UHR"
success_dir <- file.path(study, "by_index", "【success】UHR")
copy_dir <- file.path(study, "by_index", "【success】UHR - 副本")

.write_linux_config <- function() {
  txt <- readLines(cfg_path, warn = FALSE)
  txt <- gsub("G:/02block_result", "/mnt/g/02block_result", txt, fixed = TRUE)
  tmp <- file.path(study, ".config_linux_repair_uhr.R")
  writeLines(txt, tmp)
  tmp
}

setwd(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/nhanes_survey_weight.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))
source(file.path(root, "R/pipeline_runner.R"))

strip_weights <- function() {
  py <- shQuote(file.path(root, "run/diabetes_dn/strip_nhanes_weight_rows_xml.py"), type = "sh")
  # 临时改 STUDY 环境：脚本内写死 diabetes 路径，故用内联 python
  script <- paste(collapse = "\n", c(
    "import os, re, shutil, tempfile, zipfile, xml.etree.ElementTree as ET",
    "STUDY = '/mnt/g/02block_result/15_hearing_loss/incidence_38341157'",
    "NS = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}",
    "WT = re.compile(r'^(WT[A-Z0-9_]+|SDMV[A-Z0-9_]*|Source_File|new_Weight|new_weight)$', re.I)",
    "ET.register_namespace('', NS['m'])",
    "def cell_value(c, ss):",
    "  t=c.get('t'); v=c.find('m:v',NS)",
    "  if t=='s' and v is not None and v.text is not None:",
    "    i=int(v.text); return ss[i] if i < len(ss) else ''",
    "  if v is not None and v.text is not None: return v.text",
    "  return ''",
    "def read_ss(z):",
    "  if 'xl/sharedStrings.xml' not in z.namelist(): return []",
    "  root=ET.fromstring(z.read('xl/sharedStrings.xml')); out=[]",
    "  for si in root.findall('m:si',NS):",
    "    out.append(''.join((t.text or '') for t in si.findall('.//m:t',NS)))",
    "  return out",
    "n=0",
    "bi=os.path.join(STUDY,'by_index')",
    "for idx in os.listdir(bi):",
    "  if 'UHR' not in idx: continue",
    "  for rootdir,_,files in os.walk(os.path.join(bi,idx)):",
    "    for fn in files:",
    "      if not fn.endswith('.xlsx') or 'NHANES' not in fn: continue",
    "      p=os.path.join(rootdir,fn)",
    "      try:",
    "        with tempfile.TemporaryDirectory() as td:",
    "          tmp=os.path.join(td,'out.xlsx'); shutil.copy2(p,tmp)",
    "          with zipfile.ZipFile(tmp,'a') as z:",
    "            sh=[n for n in z.namelist() if n.startswith('xl/worksheets/sheet') and n.endswith('.xml')][0]",
    "            ss=read_ss(z); rootx=ET.fromstring(z.read(sh)); drop=set()",
    "            for row in rootx.findall('m:sheetData/m:row',NS):",
    "              rnum=int(row.get('r','0'))",
    "              for c in row.findall('m:c',NS):",
    "                if not c.get('r','').startswith('A'): continue",
    "                if WT.match(str(cell_value(c,ss)).strip()): drop.add(rnum); break",
    "            if not drop: continue",
    "            sd=rootx.find('m:sheetData',NS)",
    "            for row in list(sd.findall('m:row',NS)):",
    "              if int(row.get('r','0')) in drop: sd.remove(row)",
    "            new_xml=ET.tostring(rootx,encoding='utf-8',xml_declaration=True)",
    "          with zipfile.ZipFile(p,'r') as zin, zipfile.ZipFile(tmp,'w',compression=zipfile.ZIP_DEFLATED) as zout:",
    "            for item in zin.infolist():",
    "              data=zin.read(item.filename)",
    "              if item.filename==sh: data=new_xml",
    "              zout.writestr(item,data)",
    "          shutil.move(tmp,p); n+=1; print('stripped',p)",
    "      except Exception as e:",
    "        print('fail',p,e)",
    "print('total',n)"
  ))
  tmp_py <- tempfile(fileext = ".py")
  writeLines(script, tmp_py)
  status <- system(sprintf("python3 %s", shQuote(tmp_py, type = "sh")))
  unlink(tmp_py)
  if (status != 0L) stop("weight strip failed", call. = FALSE)
}

refresh_gate_a <- function(linux_cfg) {
  ga <- file.path(study, "checkpoints/_global_harmonization/gate_a_columns.rds")
  if (file.exists(ga)) file.remove(ga)
  for (db in c("CHARLS", "NHANES")) {
    for (bn in c("index.rds", "step04_index.rds", "step03_dual_db_column_harmonize.rds",
                 "dual_db_column_harmonize.rds", "column_mapping.rds", "step02_column_mapping.rds")) {
      p <- file.path(study, "checkpoints/_shared", db, bn)
      if (file.exists(p)) file.remove(p)
    }
  }
  local_env <- new.env(parent = globalenv())
  source(linux_cfg, local = local_env)
  cfg <- local_env$config
  owd <- getwd(); on.exit(setwd(owd), add = TRUE); setwd(root)
  ga_res <- incidence_batch_ensure_gate_a(cfg, root = study, force = TRUE)
  message("Gate A mimic keep extras: ",
          paste(setdiff(ga_res$gate_a$column_keep_mimic, ga_res$gate_a$common_non_demo_cols), collapse = ", "))
  invisible(ga_res$gate_a)
}

rerun_shared <- function(linux_cfg) {
  # 绕过 run_incidence_dual_batch.R 的 extensions.json guard；直接跑共享层
  local_env <- new.env(parent = globalenv())
  source(linux_cfg, local = local_env)
  cfg <- local_env$config
  cfg$project$root <- study
  cfg$incidence_batch$output_base <- study
  owd <- getwd(); on.exit(setwd(owd), add = TRUE); setwd(root)
  source(file.path(root, "configs/indices/composite_index_vars.R"), local = FALSE)
  for (db in c("nhanes", "mimic")) {
    shared_write <- incidence_batch_shared_ck_canonical_dir(cfg, db)
    pl_shared <- if (dual_db_is_weighted(cfg, db)) {
      local_env$pipeline_shared_nhanes
    } else {
      local_env$pipeline_shared_regular
    }
    # 删旧 index 强制重跑
    for (bn in c("index.rds", "step04_index.rds")) {
      p <- file.path(shared_write, bn)
      if (file.exists(p)) file.remove(p)
    }
    cli::cli_h2("共享层 [{dual_db_slot_path_name(cfg, db)}]")
    incidence_batch_run_shared_layer(root, cfg, db, pl_shared, shared_write)
  }
}

purge_uhr_ck <- function() {
  ck <- file.path(study, "checkpoints/by_index", ix)
  if (dir.exists(ck)) unlink(ck, recursive = TRUE)
  message("removed: ", ck)
}

rerun_uhr <- function(linux_cfg) {
  cmd <- paste(
    "MEDICAL_BLOCKS_ROOT=", shQuote(root, type = "sh"),
    " INCIDENCE_BATCH_ROOT=", shQuote(study, type = "sh"),
    " Rscript ", shQuote(file.path(root, "run/incidence/run_incidence_dual_batch_worker.R"), type = "sh"),
    " --index ", ix,
    " --config ", shQuote(linux_cfg, type = "sh"),
    sep = ""
  )
  message(cmd)
  status <- system(cmd)
  if (status != 0L) stop("UHR worker failed", call. = FALSE)
}

sync_to_copy <- function() {
  if (!dir.exists(success_dir)) stop("missing success dir: ", success_dir)
  if (!dir.exists(copy_dir)) dir.create(copy_dir, recursive = TRUE)
  for (rel in c("Tables", "Figures", "CHARLS", "NHANES")) {
    src <- file.path(success_dir, rel)
    dst <- file.path(copy_dir, rel)
    if (!dir.exists(src)) next
    if (dir.exists(dst)) unlink(dst, recursive = TRUE)
    ok <- system2("cp", c("-a", src, dst))
    if (!identical(ok, 0L)) stop("cp failed for ", rel, call. = FALSE)
    message("synced ", rel)
  }
}

linux_cfg <- .write_linux_config()
refresh_gate_a(linux_cfg)
rerun_shared(linux_cfg)
purge_uhr_ck()
rerun_uhr(linux_cfg)
sync_to_copy()
strip_weights()
message("done: hearing-loss UHR CHARLS labels + NHANES weights")
