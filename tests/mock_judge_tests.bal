import MathTutor.eval;

import ballerina/ai;
import ballerina/test;
import ballerinax/ai.anthropic;

// ***** Mocked LLM-judge scenario tests *****
//
// These tests replace BOTH the agent and the judge with mocks, so every
// LLM-as-judge evaluation scenario (pass, boundary, fail, multi-trace,
// reference-based) is verified deterministically, offline, and with zero
// LLM cost. Run only these with:  bal test --groups mock-evaluations

// Mirrors the judge output shape the eval module expects from generate().
type MockVerdict record {|
    float evalScore;
    string judgeReasoning;
|};

// Builds a mocked agent whose run() always produces the given response.
function newMockAgent(string mockResponse) returns ai:Agent {
    ai:Agent agentMock = test:mock(ai:Agent);
    ai:Trace mockTrace = {
        id: "mock-trace",
        userMessage: {role: "user", content: "mock query"},
        iterations: [],
        output: {role: "assistant", content: mockResponse},
        tools: [],
        startTime: [0, 0.0],
        endTime: [1, 0.0]
    };
    test:prepare(agentMock).when("run").thenReturn(mockTrace);
    return agentMock;
}

// Builds a mocked judge whose generate() always returns the given verdict.
function newMockJudge(float evalScore, string judgeReasoning) returns ai:ModelProvider {
    anthropic:ModelProvider judgeMock = test:mock(anthropic:ModelProvider);
    MockVerdict mockVerdict = {evalScore, judgeReasoning};
    test:prepare(judgeMock).when("generate").thenReturn(mockVerdict);
    return judgeMock;
}

// Builds an in-memory eval set trace with the given query and expected response.
function newMockTrace(string userQuery, string expectedResponse) returns readonly & ai:Trace {
    return {
        id: "mock-expected-trace",
        userMessage: {role: "user", content: userQuery},
        iterations: [],
        output: {role: "assistant", content: expectedResponse},
        tools: [],
        startTime: [0, 0.0],
        endTime: [1, 0.0]
    };
}

// Scenario: judge scores above the threshold -> evaluation passes.
@test:Config {
    groups: ["mock-evaluations"]
}
function judgeAboveThresholdPasses() returns error? {
    check eval:evaluateHelpfulness(targetAgent = newMockAgent("The answer is 2."),
            queries = "whats 1+1", judgeModel = newMockJudge(0.9, "mock: very helpful"),
            judgeScoreThreshold = 0.75);
}

// Scenario: judge scores exactly at the threshold -> evaluation passes (>= semantics).
@test:Config {
    groups: ["mock-evaluations"]
}
function judgeAtExactThresholdPasses() returns error? {
    check eval:evaluateHelpfulness(targetAgent = newMockAgent("The answer is 2."),
            queries = "whats 1+1", judgeModel = newMockJudge(0.75, "mock: just helpful enough"),
            judgeScoreThreshold = 0.75);
}

// Scenario: judge scores below the threshold -> evaluation fails, and the error
// carries the metric name, the score, and the judge's reasoning.
@test:Config {
    groups: ["mock-evaluations"]
}
function judgeBelowThresholdFails() {
    error? evalResult = eval:evaluateHelpfulness(targetAgent = newMockAgent("Some unhelpful text."),
            queries = "whats 1+1", judgeModel = newMockJudge(0.25, "mock: does not help the user"),
            judgeScoreThreshold = 0.75);
    if evalResult is () {
        test:assertFail("expected the evaluation to fail when the judge score is below the threshold");
    }
    string failureMessage = evalResult.message();
    test:assertTrue(failureMessage.includes("[helpfulness]"), "metric name missing from failure");
    test:assertTrue(failureMessage.includes("0.25"), "judge score missing from failure");
    test:assertTrue(failureMessage.includes("mock: does not help the user"),
            "judge reasoning missing from failure");
}

// Scenario: a thread with two traces where the judge passes the first and fails
// the second -> the whole thread fails, reporting the second query.
@test:Config {
    groups: ["mock-evaluations"]
}
function judgeFailsOnSecondTraceOfThread() {
    ai:ConversationThread mockThread = {
        id: "mock-thread",
        description: "two-trace mock thread",
        traces: [newMockTrace("query one", "expected one"), newMockTrace("query two", "expected two")]
    };
    anthropic:ModelProvider judgeMock = test:mock(anthropic:ModelProvider);
    test:prepare(judgeMock).when("generate").thenReturnSequence(
            <MockVerdict>{evalScore: 0.9, judgeReasoning: "mock: first is fine"},
            <MockVerdict>{evalScore: 0.3, judgeReasoning: "mock: second is bad"});
    error? evalResult = eval:evaluateHelpfulness(targetAgent = newMockAgent("mock response"),
            queries = mockThread, judgeModel = judgeMock, judgeScoreThreshold = 0.75);
    if evalResult is () {
        test:assertFail("expected the thread to fail on its second trace");
    }
    string failureMessage = evalResult.message();
    test:assertTrue(failureMessage.includes("query two"), "failure should name the second query");
    test:assertTrue(failureMessage.includes("0.3"), "failure should carry the second score");
}

// Scenario: reference-based judge (semantic similarity) failing -> the error
// names the metric and carries the mocked verdict.
@test:Config {
    groups: ["mock-evaluations"]
}
function judgeSemanticSimilarityFails() {
    ai:ConversationThread mockThread = {
        id: "mock-thread",
        description: "single-trace mock thread",
        traces: [newMockTrace("whats 1+1", "The answer is 2.")]
    };
    error? evalResult = eval:evaluateSemanticSimilarity(targetAgent = newMockAgent("The answer is 5."),
            thread = mockThread, judgeModel = newMockJudge(0.0, "mock: contradicts the expected answer"),
            judgeScoreThreshold = 0.75);
    if evalResult is () {
        test:assertFail("expected semantic similarity to fail");
    }
    string failureMessage = evalResult.message();
    test:assertTrue(failureMessage.includes("[semantic-similarity]"), "metric name missing from failure");
    test:assertTrue(failureMessage.includes("mock: contradicts the expected answer"),
            "judge reasoning missing from failure");
}

// Scenario: accuracy on a single query with a perfect judge score -> passes.
@test:Config {
    groups: ["mock-evaluations"]
}
function judgeAccuracyQueryPasses() returns error? {
    check eval:evaluateOutputAccuracy(targetAgent = newMockAgent("1 + 1 = 2"),
            queries = "whats 1+1", judgeModel = newMockJudge(1.0, "mock: fully correct"),
            judgeScoreThreshold = 0.75);
}
