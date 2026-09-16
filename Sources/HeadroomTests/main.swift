import Foundation
if CommandLine.arguments.contains("--state") { printLiveState(); exit(0) }
runProcessScannerTests()
runRankerTests()
runPressureTests()
runRateTests()
runColdStartTests()
runNudgePolicyTests()
runNudgeRecommendationTests()
T.finish()
