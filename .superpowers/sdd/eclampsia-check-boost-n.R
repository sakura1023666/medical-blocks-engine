load("G:/02block_result/27_eclampsia/small sample prediction_39780007/Data/mimic/dabiao_boost.RData")
dn <- as.character(dabiao$DN)
cat(sprintf("boost n=%d Case=%d Control=%d ratio=1:%.2f\n",
            nrow(dabiao), sum(dn == "Case"), sum(dn == "Control"),
            sum(dn == "Control") / max(1, sum(dn == "Case"))))
