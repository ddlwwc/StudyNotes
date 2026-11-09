export {};

declare global {
  interface Window {
    studyNotes?: {
      chooseWorkspaceDirectory: () => Promise<string | null>;
    };
  }
}
