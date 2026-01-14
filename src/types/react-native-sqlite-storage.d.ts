declare module 'react-native-sqlite-storage' {
  export interface DatabaseParams {
    name: string;
    location?: string;
    createFromLocation?: string;
  }

  export interface ResultSet {
    insertId?: number;
    rowsAffected: number;
    rows: {
      length: number;
      item(index: number): any;
      raw(): any[];
    };
  }

  export interface SQLiteDatabase {
    executeSql(
      statement: string,
      params?: any[],
    ): Promise<[ResultSet]>;
    close(): Promise<void>;
  }

  export interface SQLite {
    enablePromise(enable: boolean): void;
    openDatabase(params: DatabaseParams): Promise<SQLiteDatabase>;
  }

  const SQLite: SQLite;
  export default SQLite;
}
