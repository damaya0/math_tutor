import MathTutor.eval;

import ballerina/ai;
import ballerina/test;



isolated function loadEvalsetData1() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests/resources/evalsets/mathtutor1.evalset.json");
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadEvalsetData1
}
function flowTester(ai:ConversationThread thread) returns error? {
}

isolated function loadEvalsetData2() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests/resources/evalsets/mathtutor1.evalset.json");
}

@test:Config {
    groups: ["evaluations"],
    dependsOn: [],
    minPassRate: 0.4,
    dataProvider: loadEvalsetData2
}
function mathTuteEval(ai:ConversationThread thread) returns error? {
    foreach ai:Trace trace in thread.traces {
        ai:Trace actualTrace = check mathTutorAgent.run(trace.userMessage.content.toString(), "thread.id");
        test:assertEquals(actualTrace.toolCalls, trace.toolCalls);
    }
}


// ***************Evaluation library codes****************

// Length complient (Rule based, With Eval set)

configurable int minResponseLength = 1;
configurable int maxResponseLength = 100000;

isolated function loadEvalsetData4() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests/resources/evalsets/mathtutor1.evalset.json");
}

@test:Config {
    groups: ["evaluations"],
    dependsOn: [],
    minPassRate: 0.8,
    dataProvider: loadEvalsetData4
}
function compareLength(ai:ConversationThread thread) returns error? {
    foreach ai:Trace trace in thread.traces {
        ai:Trace actualTrace = check mathTutorAgent.run(trace.userMessage.content.toString(), "thread.id");
        ai:ChatAssistantMessage output = check actualTrace.output;
        test:assertTrue(output.content.toString().length() > minResponseLength && output.content.toString().length() < maxResponseLength);
    }
}

// Length complient (Rule based, No Eval set)
configurable map<[string]> userQueries = {
    "test": ["whats 1+1"]
};

isolated function loadUserQueries() returns map<[string]>|error {
    return userQueries;
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadUserQueries
}
function customQueryLengthCheck(string userQuery) returns error? {
    ai:Trace actualTrace = check mathTutorAgent.run(userQuery, "custom_query_session");
    ai:ChatAssistantMessage output = check actualTrace.output;
    string outputContent = output.content.toString();
    test:assertTrue(outputContent.length() > minResponseLength && outputContent.length() < maxResponseLength);
}


// Tool Trajectory (Rule based, Eval set)

isolated function loadEvalsetData() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests/resources/evalsets/math-tutor.evalset.json");
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadEvalsetData
}
function testToolTrajectory(ai:ConversationThread thread) returns error? {
    foreach ai:Trace trace in thread.traces {
        ai:Trace actualTrace = check mathTutorAgent.run(string `${trace.userMessage.content.toString()}`, string `${thread.id}`);
        test:assertEquals(actualTrace.toolCalls, trace.toolCalls);
    }
}


// Semantic Similarity (LLM, (Only) Eval set)

isolated function loadEvalsetData3() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests\\resources\\evalsets\\mathtutor1.evalset.json");
}

final ai:Wso2ModelProvider aiWso2modelprovider = check ai:getDefaultModelProvider();

@test:Config {
    groups: ["evaluations"],
    dependsOn: [],
    minPassRate: 0.9,
    dataProvider: loadEvalsetData3
}
function semanticSimilarity(ai:ConversationThread thread) returns error? {
    float judgeScoreThreshold = 0.75;
    foreach ai:Trace trace in thread.traces {
        ai:Trace actualTrace = check mathTutorAgent.run(trace.userMessage.content.toString(), thread.id);
        ai:ChatAssistantMessage actualOutput = check actualTrace.output;
        ai:ChatAssistantMessage expectedOutput = check trace.output;
        float td = check aiWso2modelprovider->generate(`You are an expert evaluator. Your sole criterion is SEMANTIC SIMILARITY: does the actual response convey the same meaning as the expected response?

        User Query: ${trace.userMessage.content.toString()}
        Actual Response: ${actualOutput.content.toString()}
        Expected Response: ${expectedOutput.content.toString()}
        Evaluation Steps:
        1. Identify the key facts, conclusions, and meaning in the expected response.
        2. Identify the same elements in the actual response.
        3. Compare for semantic equivalence: focus on MEANING, not exact wording. Paraphrases and synonymous expressions count as matches.
        4. Identify any meaningful factual differences that change the answer.

        Do NOT penalize differences in wording, formatting, or phrasing. Only deduct for genuinely different content or meaning.

        Scoring Rubric:
        0.0  = Completely different meaning; the actual response answers a different question or provides contradictory information
        0.25 = Some surface similarity but the core answer or key facts differ
        0.5  = Partially overlapping meaning; some key facts match but others differ
        0.75 = Mostly equivalent; only minor factual nuances differ
        1.0  = Semantically equivalent: same meaning, same key facts, even if worded differently`);
        test:assertEquals(true, td >= judgeScoreThreshold);
    }
}


// Accuracy (LLM, Eval set)

isolated function loadEvalsetData5() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests\\resources\\evalsets\\mathtutor1.evalset.json");
}

final ai:Wso2ModelProvider aiWso2modelprovider1 = check ai:getDefaultModelProvider();

@test:Config {
    groups: ["evaluations"],
    dependsOn: [],
    minPassRate: 0.9,
    dataProvider: loadEvalsetData5
}
function accuracy(ai:ConversationThread thread) returns error? {
    float judgeScoreThreshold = 0.75;
    foreach ai:Trace trace in thread.traces {
        ai:Trace actualTrace = check mathTutorAgent.run(trace.userMessage.content.toString(), thread.id);
        ai:ChatAssistantMessage actualOutput = check actualTrace.output;
        float td = check aiWso2modelprovider1->generate(`You are an expert evaluator. Your sole criterion is ACCURACY: is the factual information in the response correct and reliable?

        User Query: ${trace.userMessage.content.toString()}
        Agent Response: ${actualOutput.content.toString()}

        Evaluation Steps:
        1. Identify the factual claims, technical statements, and information presented in the response.
        2. Assess whether these facts are correct based on your knowledge. Flag any statements that are demonstrably wrong, misleading, or technically imprecise.
        3. Check for subtle inaccuracies: correct general direction but wrong specifics, outdated information presented as current, or oversimplifications that mislead.
        4. Assess the overall reliability of the information provided.

        Do NOT penalize the response for information you cannot verify. Only flag claims you are confident are incorrect or misleading.

        Scoring Rubric:
        0.0  = Contains significant factual errors that would mislead the user
        0.25 = Several inaccuracies or one major factual error that undermines trust
        0.5  = Mostly accurate but with noticeable errors or misleading simplifications
        0.75 = Accurate with only minor imprecisions that do not materially mislead
        1.0  = Fully accurate; all factual claims are correct and reliably stated`);
        test:assertEquals(true, td >= judgeScoreThreshold);
    }
}


// Accuracy (LLM, No Eval set)
// wso2 model provider is resued

configurable map<[string]> accuracyQueries = {
    "test": ["whats 1+1"]
};

isolated function loadAccuracyQueries() returns map<[string]>|error {
    return accuracyQueries;
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadAccuracyQueries
}
function customQueryAccuracy(string userQuery) returns error? {
    float judgeScoreThreshold = 0.8;
    ai:Trace actualTrace = check mathTutorAgent.run(userQuery, "accuracy_query_session");
    float td = check aiWso2modelprovider1->generate(`You are an expert evaluator. Your sole criterion is ACCURACY: is the factual information in the response correct and reliable?

        User Query: ${userQuery}
        Agent Response: ${check actualTrace.output}

        Evaluation Steps:
        1. Identify the factual claims, technical statements, and information presented in the response.
        2. Assess whether these facts are correct based on your knowledge. Flag any statements that are demonstrably wrong, misleading, or technically imprecise.
        3. Check for subtle inaccuracies: correct general direction but wrong specifics, outdated information presented as current, or oversimplifications that mislead.
        4. Assess the overall reliability of the information provided.

        Do NOT penalize the response for information you cannot verify. Only flag claims you are confident are incorrect or misleading.

        Scoring Rubric:
        0.0  = Contains significant factual errors that would mislead the user
        0.25 = Several inaccuracies or one major factual error that undermines trust
        0.5  = Mostly accurate but with noticeable errors or misleading simplifications
        0.75 = Accurate with only minor imprecisions that do not materially mislead
        1.0  = Fully accurate; all factual claims are correct and reliably stated`);
    test:assertEquals(true, td >= judgeScoreThreshold);
}


// ***************Evaluations using the MathTutor.eval library****************
//
// Each block below is what the low-code interface would generate for a default
// evaluation template using the eval library. Every template collapses to a
// single call: run the agent, score it, and fail with a descriptive error
// (a failure feeds the minPassRate calculation).
//
// When the module is published as ballerina/ai.eval, only the import changes.

final ai:ModelProvider evalJudgeModel = check ai:getDefaultModelProvider();

isolated function loadLibraryEvalset() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests/resources/evalsets/mathtutor1.evalset.json");
}

// Length compliance (rule based, with eval set)

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibraryEvalset
}
function libLengthCompliance(ai:ConversationThread thread) returns error? {
    check eval:assertLengthCompliance(targetAgent = mathTutorAgent, thread = thread,
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
function libQueryLengthCompliance(string userQuery) returns error? {
    check eval:evaluateLengthComplianceForQuery(targetAgent = mathTutorAgent, userQuery = userQuery,
            minLength = minResponseLength, maxLength = maxResponseLength);
}

// Tool trajectory (rule based, with eval set)

isolated function loadLibraryTrajectoryEvalset() returns map<[ai:ConversationThread]>|error {
    return ai:loadConversationThreads("tests/resources/evalsets/math-tutor.evalset.json");
}

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.8,
    dataProvider: loadLibraryTrajectoryEvalset
}
function libToolTrajectory(ai:ConversationThread thread) returns error? {
    check eval:evaluateToolTrajectory(targetAgent = mathTutorAgent, thread = thread);
}

// Semantic similarity (LLM as judge, with eval set)

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryEvalset
}
function libSemanticSimilarity(ai:ConversationThread thread) returns error? {
    check eval:evaluateSemanticSimilarity(targetAgent = mathTutorAgent, thread = thread,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.75);
}

// Accuracy (LLM as judge, with eval set)

@test:Config {
    groups: ["evaluations"],
    minPassRate: 0.9,
    dataProvider: loadLibraryEvalset
}
function libAccuracy(ai:ConversationThread thread) returns error? {
    check eval:evaluateOutputAccuracy(targetAgent = mathTutorAgent, thread = thread,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.875);
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
function libQueryAccuracy(string userQuery) returns error? {
    check eval:evaluateOutputAccuracyForQuery(targetAgent = mathTutorAgent, userQuery = userQuery,
            judgeModel = evalJudgeModel, judgeScoreThreshold = 0.8);
}
