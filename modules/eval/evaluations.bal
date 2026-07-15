import ballerina/ai;

# Default session ID used when evaluating standalone user queries.
const string DEFAULT_EVAL_SESSION = "eval-session";

// ***** Rule-based evaluations *****

# Checks that the length of every agent response for the thread falls within the
# given bounds (inclusive).
#
# + targetAgent - The agent under evaluation
# + thread - The conversation thread loaded from an eval set
# + minLength - The minimum accepted response length (inclusive)
# + maxLength - The maximum accepted response length (inclusive)
# + return - `()` if every trace passes, or an error describing the first failure
@EvalTemplate {
    label: "Length Compliance (Eval Set)",
    description: "Checks that every agent response length stays within the configured bounds",
    kind: RULE_BASED,
    needsEvalset: true
}
public isolated function assertLengthCompliance(ai:Agent targetAgent, ai:ConversationThread thread,
        int minLength = 1, int maxLength = 100000) returns error? {
    foreach ai:Trace expectedTrace in thread.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        string actualResponse = check getAgentResponse(targetAgent = targetAgent, userQuery = userQuery,
                sessionId = thread.id);
        check checkLength(userQuery = userQuery, actualResponse = actualResponse,
                minLength = minLength, maxLength = maxLength);
    }
}

# Checks that the length of the agent response for a standalone query falls within
# the given bounds (inclusive).
#
# + targetAgent - The agent under evaluation
# + userQuery - The query to send to the agent
# + minLength - The minimum accepted response length (inclusive)
# + maxLength - The maximum accepted response length (inclusive)
# + sessionId - The memory session ID to run the agent with
# + return - `()` on success, or an error describing the failure
@EvalTemplate {
    label: "Length Compliance (Custom Query)",
    description: "Checks that the agent response length for a single query stays within the configured bounds",
    kind: RULE_BASED,
    needsEvalset: false
}
public isolated function evaluateLengthComplianceForQuery(ai:Agent targetAgent, string userQuery,
        int minLength = 1, int maxLength = 100000, string sessionId = DEFAULT_EVAL_SESSION) returns error? {
    string actualResponse = check getAgentResponse(targetAgent = targetAgent, userQuery = userQuery,
            sessionId = sessionId);
    check checkLength(userQuery = userQuery, actualResponse = actualResponse,
            minLength = minLength, maxLength = maxLength);
}

# Checks that the agent invokes the same tools, in the same order and with the same
# arguments, as recorded in the eval set. Tool-call IDs are ignored since they differ
# between runs.
#
# + targetAgent - The agent under evaluation
# + thread - The conversation thread loaded from an eval set
# + return - `()` if every trace passes, or an error describing the first mismatch
@EvalTemplate {
    label: "Tool Trajectory",
    description: "Checks that the agent invokes the same tools with the same arguments as the eval set",
    kind: RULE_BASED,
    needsEvalset: true
}
public isolated function evaluateToolTrajectory(ai:Agent targetAgent, ai:ConversationThread thread)
        returns error? {
    foreach ai:Trace expectedTrace in thread.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        ai:Trace actualTrace = check targetAgent.run(query = userQuery, sessionId = thread.id);
        ai:FunctionCall[] expectedToolCalls = expectedTrace.toolCalls ?: [];
        ai:FunctionCall[] actualToolCalls = actualTrace.toolCalls ?: [];
        if !matchToolCalls(expectedToolCalls = expectedToolCalls, actualToolCalls = actualToolCalls) {
            return error(string `[tool-trajectory] query "${userQuery}": expected tool calls ${describeToolCalls(toolCalls = expectedToolCalls)} but got ${describeToolCalls(toolCalls = actualToolCalls)}`);
        }
    }
}

// ***** LLM-as-judge evaluations *****

# Uses an LLM judge to check that every agent response for the thread conveys the
# same meaning as the reference response recorded in the eval set.
#
# + targetAgent - The agent under evaluation
# + thread - The conversation thread loaded from an eval set
# + judgeModel - The model provider used as the LLM judge
# + judgeScoreThreshold - The minimum judge score (in [0.0, 1.0]) required to pass
# + return - `()` if every trace passes, or an error describing the first failure
@EvalTemplate {
    label: "Semantic Similarity",
    description: "Uses an LLM judge to compare each agent response against the expected response in the eval set",
    kind: LLM_JUDGE,
    needsEvalset: true
}
public isolated function evaluateSemanticSimilarity(ai:Agent targetAgent, ai:ConversationThread thread,
        ai:ModelProvider judgeModel, float judgeScoreThreshold = 0.8) returns error? {
    foreach ai:Trace expectedTrace in thread.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        ai:ChatAssistantMessage expectedOutput = check expectedTrace.output;
        ai:Trace actualTrace = check targetAgent.run(query = userQuery, sessionId = thread.id);
        ai:ChatAssistantMessage actualOutput = check actualTrace.output;
        float evalScore = check judgeModel->generate(`You are an expert evaluator. Your sole criterion is SEMANTIC SIMILARITY: does the actual response convey the same meaning as the expected response?

        User Query: ${userQuery}
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
        check checkScore(metricName = "semantic-similarity", userQuery = userQuery,
                evalScore = evalScore, passingScore = judgeScoreThreshold);
    }
}

# Uses an LLM judge to check that the factual information in every agent response
# for the thread is correct and reliable.
#
# + targetAgent - The agent under evaluation
# + thread - The conversation thread loaded from an eval set
# + judgeModel - The model provider used as the LLM judge
# + judgeScoreThreshold - The minimum judge score (in [0.0, 1.0]) required to pass
# + return - `()` if every trace passes, or an error describing the first failure
@EvalTemplate {
    label: "Output Accuracy (Eval Set)",
    description: "Uses an LLM judge to check the factual correctness of each agent response in the eval set",
    kind: LLM_JUDGE,
    needsEvalset: true
}
public isolated function evaluateOutputAccuracy(ai:Agent targetAgent, ai:ConversationThread thread,
        ai:ModelProvider judgeModel, float judgeScoreThreshold = 0.8) returns error? {
    foreach ai:Trace expectedTrace in thread.traces {
        string userQuery = ai:getUserQuery(trace = expectedTrace);
        check evaluateOutputAccuracyForQuery(targetAgent = targetAgent, userQuery = userQuery,
                judgeModel = judgeModel, judgeScoreThreshold = judgeScoreThreshold, sessionId = thread.id);
    }
}

# Uses an LLM judge to check that the factual information in the agent response for
# a standalone query is correct and reliable.
#
# + targetAgent - The agent under evaluation
# + userQuery - The query to send to the agent
# + judgeModel - The model provider used as the LLM judge
# + judgeScoreThreshold - The minimum judge score (in [0.0, 1.0]) required to pass
# + sessionId - The memory session ID to run the agent with
# + return - `()` on success, or an error describing the failure
@EvalTemplate {
    label: "Output Accuracy (Custom Query)",
    description: "Uses an LLM judge to check the factual correctness of the agent response to a single query",
    kind: LLM_JUDGE,
    needsEvalset: false
}
public isolated function evaluateOutputAccuracyForQuery(ai:Agent targetAgent, string userQuery,
        ai:ModelProvider judgeModel, float judgeScoreThreshold = 0.8, string sessionId = DEFAULT_EVAL_SESSION)
        returns error? {
    ai:Trace actualTrace = check targetAgent.run(query = userQuery, sessionId = sessionId);
    ai:ChatAssistantMessage actualOutput = check actualTrace.output;
    float evalScore = check judgeModel->generate(`You are an expert evaluator. Your sole criterion is ACCURACY: is the factual information in the response correct and reliable?

        User Query: ${userQuery}
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
    check checkScore(metricName = "accuracy", userQuery = userQuery,
            evalScore = evalScore, passingScore = judgeScoreThreshold);
}

// ***** Shared helpers *****

isolated function getAgentResponse(ai:Agent targetAgent, string userQuery, string sessionId)
        returns string|error {
    ai:Trace actualTrace = check targetAgent.run(query = userQuery, sessionId = sessionId);
    return getResponseText(trace = actualTrace);
}

isolated function getResponseText(ai:Trace trace) returns string|error {
    ai:ChatAssistantMessage output = check trace.output;
    return output.content ?: "";
}

isolated function checkLength(string userQuery, string actualResponse, int minLength, int maxLength)
        returns error? {
    int responseLength = actualResponse.length();
    if responseLength < minLength || responseLength > maxLength {
        return error(string `[length-compliance] query "${userQuery}": response length ${responseLength} is outside the range [${minLength}, ${maxLength}]`);
    }
}

isolated function checkScore(string metricName, string userQuery, float evalScore, float passingScore)
        returns error? {
    if evalScore < passingScore {
        return error(string `[${metricName}] query "${userQuery}": judge score ${evalScore} is below the passing score ${passingScore}`);
    }
}

isolated function matchToolCalls(ai:FunctionCall[] expectedToolCalls, ai:FunctionCall[] actualToolCalls)
        returns boolean {
    if expectedToolCalls.length() != actualToolCalls.length() {
        return false;
    }
    foreach int callIndex in 0 ..< expectedToolCalls.length() {
        ai:FunctionCall expectedCall = expectedToolCalls[callIndex];
        ai:FunctionCall actualCall = actualToolCalls[callIndex];
        if expectedCall.name != actualCall.name || expectedCall.arguments != actualCall.arguments {
            return false;
        }
    }
    return true;
}

isolated function describeToolCalls(ai:FunctionCall[] toolCalls) returns string {
    string[] callDescriptions = toolCalls.'map(toolCall =>
        string `${toolCall.name}(${(toolCall.arguments ?: {}).toJsonString()})`);
    return "[" + string:'join(", ", ...callDescriptions) + "]";
}
