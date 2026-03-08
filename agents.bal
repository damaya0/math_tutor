import ballerina/ai;

final ai:Agent mathTutorAgent = check new (
    systemPrompt = {
        role: string `Math Tutor`,
        instructions: string `You are a math tutor assistant.

RULES (MUST FOLLOW):

* You MUST use the provided mathematical tools (add, subtract, multiply, divide) for ALL calculations, even simple ones.
* You are NOT allowed to compute results mentally or inline.
* If a calculation is required and a tool is available, you MUST call the tool.
* If you do not call a tool when a calculation is required, the response is invalid.

Provide clear, step-by-step explanations. Include the final answer at the end.`
    }, memory = aiShorttermmemory, model = mathTutorModel, tools = [sumTool, subtractTool, multiplyTool, divideTool], verbose = false
);

# Calculates the sum of two numbers
@ai:AgentTool
@display {label: "", iconPath: ""}
isolated function sumTool(float num1, float num2) returns float {
    float result = sum(num1, num2);
    return result;
}

# Calculates the difference of two numbers
@ai:AgentTool
@display {label: "", iconPath: ""}
isolated function subtractTool(float num1, float num2) returns float {
    float result = subtract(num1, num2);
    return result;
}

# Calculates the product of two numbers
@ai:AgentTool
@display {label: "", iconPath: ""}
isolated function multiplyTool(float num1, float num2) returns float {
    float result = multiply(num1, num2);
    return result;
}

# Calculates the division of two numbers
# Handles division by zero
# If num2 is zero, returns 0
# Otherwise, returns the result of the division
@ai:AgentTool
@display {label: "", iconPath: ""}
isolated function divideTool(float num1, float num2) returns float {
    if (num2 == 0.0) {
        return 0.0;
    }
    float result = divide(num1, num2);
    return result;
}

final ai:ShortTermMemory aiShorttermmemory = check new (aiInmemoryshorttermmemorystore);

final ai:InMemoryShortTermMemoryStore aiInmemoryshorttermmemorystore = check new (10);
