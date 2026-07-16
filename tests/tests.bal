import MathTutor.eval;

import ballerina/ai;
import ballerina/test;
import ballerinax/ai.anthropic;

// ***************Evaluations using the MathTutor.eval library****************
//
// Each block below is what the low-code interface would generate for a default
// evaluation template using the eval library. Every template collapses to a
// single call: run the agent, score it, and fail with a descriptive error
// (a failure feeds the minPassRate calculation).
//
// When the module is published as ballerina/ai.eval, only the import changes.

// LLM judge: Anthropic Claude at temperature 0 so identical inputs always score
// identically. Paste the real API key as the default below, or override it at the
// TOP LEVEL of tests/Config.toml with: anthropicApiKey = "sk-ant-..."
configurable string anthropicApiKey = "key";

final ai:ModelProvider evalJudgeModel = check new anthropic:ModelProvider(apiKey = anthropicApiKey,
        modelType = anthropic:CLAUDE_SONNET_4_5, temperature = 0.0);

isolated function loadLibraryEvalset() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests/resources/evalsets/mathtutor1.evalset.json");
}

// Length compliance (rule based, with eval set)

configurable int minResponseLength = 1;
configurable int maxResponseLength = 100000;

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibraryEvalset
}
function lengthCompliance(ai:ConversationThread thread) returns error? {
    check eval:assertLengthCompliance(targetAgent = mathTutorAgent, queries = thread,
            minLength = minResponseLength, maxLength = maxResponseLength);
}

// Length compliance (rule based, no eval set)

configurable map<[string]> libraryUserQueries = {
    "test": ["whats 1+1"]
};

isolated function loadLibraryUserQueries() returns map<[string]>|error {
    return libraryUserQueries;
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibraryUserQueries
}
function queryLengthCompliance(string userQuery) returns error? {
    check eval:assertLengthCompliance(targetAgent = mathTutorAgent, queries = userQuery,
            minLength = minResponseLength, maxLength = maxResponseLength);
}

// Exact match (rule based, with eval set)

isolated function loadLibraryEvalsetExact() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests/resources/evalsets/exactMatchEval.evalset.json");
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibraryEvalsetExact
}
function exactMatch(ai:ConversationThread thread) returns error? {
    check eval:assertExactMatch(targetAgent = mathTutorAgent, thread = thread);
}

// Tool trajectory (rule based, with eval set) — one test per matching mode

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibraryEvalset
}
function toolTrajectoryStrict(ai:ConversationThread thread) returns error? {
    check eval:evaluateToolTrajectory(targetAgent = mathTutorAgent, thread = thread,
            matchMode = eval:STRICT);
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibraryEvalset
}
function toolTrajectoryUnordered(ai:ConversationThread thread) returns error? {
    check eval:evaluateToolTrajectory(targetAgent = mathTutorAgent, thread = thread,
            matchMode = eval:UNORDERED);
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibraryEvalset
}
function toolTrajectorySubset(ai:ConversationThread thread) returns error? {
    check eval:evaluateToolTrajectory(targetAgent = mathTutorAgent, thread = thread,
            matchMode = eval:SUBSET);
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibraryEvalset
}
function toolTrajectorySuperset(ai:ConversationThread thread) returns error? {
    check eval:evaluateToolTrajectory(targetAgent = mathTutorAgent, thread = thread,
            matchMode = eval:SUPERSET);
}

// Semantic similarity (LLM as judge, with eval set)

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryEvalset
}
function semanticSimilarity(ai:ConversationThread thread) returns error? {
    check eval:evaluateSemanticSimilarity(targetAgent = mathTutorAgent, thread = thread,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

// Accuracy (LLM as judge, with eval set)

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryEvalset
}
function accuracy(ai:ConversationThread thread) returns error? {
    check eval:evaluateOutputAccuracy(targetAgent = mathTutorAgent, queries = thread,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

// Accuracy (LLM as judge, no eval set)

configurable map<[string]> libraryAccuracyQueries = {
    "test": ["whats 1+1"]
};

isolated function loadLibraryAccuracyQueries() returns map<[string]>|error {
    return libraryAccuracyQueries;
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryAccuracyQueries
}
function queryAccuracy(string userQuery) returns error? {
    check eval:evaluateOutputAccuracy(targetAgent = mathTutorAgent, queries = userQuery,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

// Content safety (rule based, with eval set)

configurable string[] prohibitedContent = ["as an AI language model", "I refuse to help"];

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibraryEvalset
}
function contentSafety(ai:ConversationThread thread) returns error? {
    check eval:assertContentSafety(targetAgent = mathTutorAgent, queries = thread,
            prohibitedStrings = prohibitedContent);
}

// Content safety (rule based, no eval set)

configurable map<[string]> librarySafetyQueries = {
    "test": ["whats 1+1"]
};

isolated function loadLibrarySafetyQueries() returns map<[string]>|error {
    return librarySafetyQueries;
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibrarySafetyQueries
}
function queryContentSafety(string userQuery) returns error? {
    check eval:assertContentSafety(targetAgent = mathTutorAgent, queries = userQuery,
            prohibitedStrings = prohibitedContent);
}

// Contains match (rule based, with eval set)

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibraryEvalset
}
function containsMatch(ai:ConversationThread thread) returns error? {
    check eval:assertContainsMatch(targetAgent = mathTutorAgent, thread = thread);
}
// Iteration efficiency (rule based, with eval set)

configurable int maxAgentIterations = 5;

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibraryEvalset
}
function iterationEfficiency(ai:ConversationThread thread) returns error? {
    check eval:assertIterationEfficiency(targetAgent = mathTutorAgent, queries = thread,
            maxIterations = maxAgentIterations);
}

// Iteration efficiency (rule based, no eval set)

configurable map<[string]> libraryIterationQueries = {
    "test": ["whats 1+1"]
};

isolated function loadLibraryIterationQueries() returns map<[string]>|error {
    return libraryIterationQueries;
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibraryIterationQueries
}
function queryIterationEfficiency(string userQuery) returns error? {
    check eval:assertIterationEfficiency(targetAgent = mathTutorAgent, queries = userQuery,
            maxIterations = maxAgentIterations);
}

// Content coverage (rule based, with eval set)

configurable string[] requiredContent = ["final answer"];

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibraryEvalset
}
function contentCoverage(ai:ConversationThread thread) returns error? {
    check eval:assertContentCoverage(targetAgent = mathTutorAgent, queries = thread,
            requiredStrings = requiredContent);
}

// Content coverage (rule based, no eval set)

configurable map<[string]> libraryCoverageQueries = {
    "test": ["whats 1+1"]
};

isolated function loadLibraryCoverageQueries() returns map<[string]>|error {
    return libraryCoverageQueries;
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibraryCoverageQueries
}
function queryContentCoverage(string userQuery) returns error? {
    check eval:assertContentCoverage(targetAgent = mathTutorAgent, queries = userQuery,
            requiredStrings = requiredContent);
}

// Latency performance (rule based, with eval set)

configurable decimal maxResponseSeconds = 10;

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibraryEvalset
}
function latencyPerformance(ai:ConversationThread thread) returns error? {
    check eval:assertLatencyPerformance(targetAgent = mathTutorAgent, queries = thread,
            maxLatencySeconds = maxResponseSeconds);
}

// Latency performance (rule based, no eval set)

configurable map<[string]> libraryLatencyQueries = {
    "test": ["whats 1+1"]
};

isolated function loadLibraryLatencyQueries() returns map<[string]>|error {
    return libraryLatencyQueries;
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibraryLatencyQueries
}
function queryLatencyPerformance(string userQuery) returns error? {
    check eval:assertLatencyPerformance(targetAgent = mathTutorAgent, queries = userQuery,
            maxLatencySeconds = maxResponseSeconds);
}

// ***** LLM-as-judge evaluations (reference-free) *****
// All judge tests share the eval set loader for thread runs and the query
// loader below for single-query runs.

configurable map<[string]> libraryJudgeQueries = {
    "test": ["whats 1+1"]
};

isolated function loadLibraryJudgeQueries() returns map<[string]>|error {
    return libraryJudgeQueries;
}

// Helpfulness

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryEvalset
}
function helpfulness(ai:ConversationThread thread) returns error? {
    check eval:evaluateHelpfulness(targetAgent = mathTutorAgent, queries = thread,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryJudgeQueries
}
function queryHelpfulness(string userQuery) returns error? {
    check eval:evaluateHelpfulness(targetAgent = mathTutorAgent, queries = userQuery,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

// Clarity

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryEvalset
}
function clarity(ai:ConversationThread thread) returns error? {
    check eval:evaluateClarity(targetAgent = mathTutorAgent, queries = thread,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryJudgeQueries
}
function queryClarity(string userQuery) returns error? {
    check eval:evaluateClarity(targetAgent = mathTutorAgent, queries = userQuery,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

// Completeness

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryEvalset
}
function completeness(ai:ConversationThread thread) returns error? {
    check eval:evaluateCompleteness(targetAgent = mathTutorAgent, queries = thread,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryJudgeQueries
}
function queryCompleteness(string userQuery) returns error? {
    check eval:evaluateCompleteness(targetAgent = mathTutorAgent, queries = userQuery,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

// Relevance

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryEvalset
}
function relevance(ai:ConversationThread thread) returns error? {
    check eval:evaluateRelevance(targetAgent = mathTutorAgent, queries = thread,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryJudgeQueries
}
function queryRelevance(string userQuery) returns error? {
    check eval:evaluateRelevance(targetAgent = mathTutorAgent, queries = userQuery,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

// Coherence

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryEvalset
}
function coherence(ai:ConversationThread thread) returns error? {
    check eval:evaluateCoherence(targetAgent = mathTutorAgent, queries = thread,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryJudgeQueries
}
function queryCoherence(string userQuery) returns error? {
    check eval:evaluateCoherence(targetAgent = mathTutorAgent, queries = userQuery,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

// Conciseness

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryEvalset
}
function conciseness(ai:ConversationThread thread) returns error? {
    check eval:evaluateConciseness(targetAgent = mathTutorAgent, queries = thread,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryJudgeQueries
}
function queryConciseness(string userQuery) returns error? {
    check eval:evaluateConciseness(targetAgent = mathTutorAgent, queries = userQuery,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

// Safety

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryEvalset
}
function safety(ai:ConversationThread thread) returns error? {
    check eval:evaluateSafety(targetAgent = mathTutorAgent, queries = thread,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryJudgeQueries
}
function querySafety(string userQuery) returns error? {
    check eval:evaluateSafety(targetAgent = mathTutorAgent, queries = userQuery,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

// Tone

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryEvalset
}
function tone(ai:ConversationThread thread) returns error? {
    check eval:evaluateTone(targetAgent = mathTutorAgent, queries = thread,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75,
            toneContext = "math tutoring for students");
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryJudgeQueries
}
function queryTone(string userQuery) returns error? {
    check eval:evaluateTone(targetAgent = mathTutorAgent, queries = userQuery,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75,
            toneContext = "math tutoring for students");
}

// Groundedness

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryEvalset
}
function groundedness(ai:ConversationThread thread) returns error? {
    check eval:evaluateGroundedness(targetAgent = mathTutorAgent, queries = thread,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryJudgeQueries
}
function queryGroundedness(string userQuery) returns error? {
    check eval:evaluateGroundedness(targetAgent = mathTutorAgent, queries = userQuery,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

// Reasoning quality

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryEvalset
}
function reasoningQuality(ai:ConversationThread thread) returns error? {
    check eval:evaluateReasoningQuality(targetAgent = mathTutorAgent, queries = thread,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryJudgeQueries
}
function queryReasoningQuality(string userQuery) returns error? {
    check eval:evaluateReasoningQuality(targetAgent = mathTutorAgent, queries = userQuery,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

// Path efficiency

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryEvalset
}
function pathEfficiency(ai:ConversationThread thread) returns error? {
    check eval:evaluatePathEfficiency(targetAgent = mathTutorAgent, queries = thread,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryJudgeQueries
}
function queryPathEfficiency(string userQuery) returns error? {
    check eval:evaluatePathEfficiency(targetAgent = mathTutorAgent, queries = userQuery,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

// Error recovery

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryEvalset
}
function errorRecovery(ai:ConversationThread thread) returns error? {
    check eval:evaluateErrorRecovery(targetAgent = mathTutorAgent, queries = thread,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryJudgeQueries
}
function queryErrorRecovery(string userQuery) returns error? {
    check eval:evaluateErrorRecovery(targetAgent = mathTutorAgent, queries = userQuery,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

// Instruction following

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryEvalset
}
function instructionFollowing(ai:ConversationThread thread) returns error? {
    check eval:evaluateInstructionFollowing(targetAgent = mathTutorAgent, queries = thread,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryJudgeQueries
}
function queryInstructionFollowing(string userQuery) returns error? {
    check eval:evaluateInstructionFollowing(targetAgent = mathTutorAgent, queries = userQuery,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}
