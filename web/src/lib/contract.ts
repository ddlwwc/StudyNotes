import fs from "node:fs";
import path from "node:path";
import Ajv2020, { type ValidateFunction } from "ajv/dist/2020";
import { parse } from "yaml";
import { AppError, ValidationError } from "@/domain/errors";

interface ContractCache {
  validators: Map<string, ValidateFunction>;
  document: unknown;
}

let cache: ContractCache | null = null;

function resolveContractPath(): string {
  const candidates = [
    process.env.OPENAPI_CONTRACT_PATH,
    path.join(process.cwd(), "contracts", "openapi.yaml"),
    path.join(process.cwd(), "..", "contracts", "openapi.yaml")
  ].filter((candidate): candidate is string => Boolean(candidate));

  const match = candidates.find((candidate) => fs.existsSync(candidate));
  if (!match) {
    throw new AppError(
      "找不到 contracts/openapi.yaml，无法执行请求边界校验",
      500,
      "CONTRACT_NOT_FOUND"
    );
  }
  return match;
}

function loadContract(): ContractCache {
  if (cache) {
    return cache;
  }

  const source = fs.readFileSync(resolveContractPath(), "utf8");
  const document = parse(source) as Record<string, unknown>;
  const ajv = new Ajv2020({
    allErrors: true,
    strict: false,
    validateFormats: false,
    useDefaults: true
  });
  ajv.addSchema(document, "openapi");

  cache = {
    document,
    validators: new Map()
  };
  return cache;
}

export function validateContract<T>(schemaName: string, value: unknown): T {
  const contract = loadContract();
  let validator = contract.validators.get(schemaName);
  if (!validator) {
    const id = `openapi#/components/schemas/${schemaName}`;
    const resolved = getAjvValidator(id, contract.document);
    if (!resolved) {
      throw new AppError(
        `OpenAPI 不存在 schema ${schemaName}`,
        500,
        "CONTRACT_SCHEMA_NOT_FOUND"
      );
    }
    validator = resolved;
    contract.validators.set(schemaName, validator);
  }

  if (!validator(value)) {
    throw new ValidationError("请求不符合 OpenAPI 契约", {
      errors: validator.errors?.map((error) => ({
        instancePath: error.instancePath,
        keyword: error.keyword,
        message: error.message,
        params: error.params
      }))
    });
  }

  return value as T;
}

function getAjvValidator(
  schemaId: string,
  document: unknown
): ValidateFunction | undefined {
  const ajv = new Ajv2020({
    allErrors: true,
    strict: false,
    validateFormats: false,
    useDefaults: true
  });
  ajv.addSchema(document as Record<string, unknown>, "openapi");
  return ajv.getSchema(schemaId);
}

export function getContractDocument<T>(): T {
  return loadContract().document as T;
}
