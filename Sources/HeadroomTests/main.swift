import Foundation
if CommandLine.arguments.contains("--state") { printLiveState(); exit(0) }
runProcessScannerTests()
runRankerTests()
runPressureTests()
runColdStartTests()
runNudgePolicyTests()
runNudgeRecommendationTests()
T.finish()
