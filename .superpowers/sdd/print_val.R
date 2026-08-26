p <- "G:/02block_result/27_eclampsia/small sample prediction_39780007/by_index/【success】UA_CR/MIMIC_IV/Tables"
fs <- list.files(p, pattern="validation\\.xlsx$", full.names=TRUE)
print(fs)
d <- openxlsx::read.xlsx(fs[1])
print(d[1:10,1:6])
cat("n_status from json\n")
