#!/usr/bin/env Rscript
# 发表数字默认：est=2 / p=3 / desc=2 / cutoff=3 / int_big_mark=TRUE
root <- normalizePath(".")
source(file.path(root, "R/utils.R"), local = FALSE)

# 清掉可能被其它测试污染的 options
options(
  medical_blocks.pub_digits.est = NULL,
  medical_blocks.pub_digits.p = NULL,
  medical_blocks.pub_digits.desc = NULL,
  medical_blocks.pub_digits.cutoff = NULL,
  medical_blocks.pub_digits.int_big_mark = NULL
)

d <- .pipeline_pub_digits()
stopifnot(identical(as.integer(d$est), 2L))
stopifnot(identical(as.integer(d$p), 3L))
stopifnot(identical(as.integer(d$desc), 2L))
stopifnot(identical(as.integer(d$cutoff), 3L))
stopifnot(isTRUE(d$int_big_mark))

stopifnot(identical(pub_format_est(1.2345), "1.23"))
stopifnot(identical(pub_format_p(0.01234), "0.012"))
stopifnot(identical(pub_format_int(4399L), "4,399"))

# 课题覆盖仍生效
pipeline_apply_pub_digits(list(pub_digits = list(est = 3L, cutoff = 4L)))
d2 <- .pipeline_pub_digits()
stopifnot(identical(as.integer(d2$est), 3L))
stopifnot(identical(as.integer(d2$cutoff), 4L))
stopifnot(identical(pub_format_est(1.2345), "1.234"))

# 恢复默认，避免污染后续进程（同会话）
options(
  medical_blocks.pub_digits.est = NULL,
  medical_blocks.pub_digits.p = NULL,
  medical_blocks.pub_digits.desc = NULL,
  medical_blocks.pub_digits.cutoff = NULL,
  medical_blocks.pub_digits.int_big_mark = NULL
)

message("OK: test_pub_digits_defaults")
