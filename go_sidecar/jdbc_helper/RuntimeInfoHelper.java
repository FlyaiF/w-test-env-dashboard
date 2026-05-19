import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;

public class RuntimeInfoHelper {
  public static void main(String[] args) throws Exception {
    String dsn = null;
    boolean testOnly = false;
    for (int i = 0; i < args.length; i++) {
      if ("--dsn".equals(args[i]) && i + 1 < args.length) {
        dsn = args[++i];
      } else if ("--test".equals(args[i])) {
        testOnly = true;
      }
    }

    if (dsn == null || dsn.trim().isEmpty()) {
      throw new IllegalArgumentException("--dsn is required");
    }

    Class.forName("com.oceanbase.jdbc.Driver");
    try (Connection conn = DriverManager.getConnection(dsn)) {
      if (testOnly) {
        try (Statement stmt = conn.createStatement();
            ResultSet rs = stmt.executeQuery("select 1 from dual")) {
          rs.next();
        }
        System.out.println("{\"ok\":true}");
        return;
      }

      String systemVersion = null;
      try (Statement stmt = conn.createStatement();
          ResultSet rs =
              stmt.executeQuery(
                  "select param_value from tsys_parameter where param_code = 'SystemVersion'")) {
        if (rs.next()) {
          systemVersion = rs.getString(1);
        }
      }

      String beginTime = null;
      String subsystemVer = null;
      try (Statement stmt = conn.createStatement();
          ResultSet rs =
              stmt.executeQuery(
                  "select * from (select begin_time, subsystem_ver from jres_subsystem_rc order by begin_time desc) where rownum = 1")) {
        if (rs.next()) {
          beginTime = rs.getString(1);
          subsystemVer = rs.getString(2);
        }
      }

      StringBuilder out = new StringBuilder();
      out.append("{");
      appendJsonField(out, "system_version", systemVersion, true);
      appendJsonField(out, "begin_time", beginTime, false);
      appendJsonField(out, "subsystem_ver", subsystemVer, false);
      out.append("}");
      System.out.println(out.toString());
    }
  }

  private static void appendJsonField(StringBuilder out, String key, String value, boolean first) {
    if (!first) {
      out.append(",");
    }
    out.append("\"").append(escape(key)).append("\":");
    if (value == null || value.trim().isEmpty()) {
      out.append("null");
    } else {
      out.append("\"").append(escape(value.trim())).append("\"");
    }
  }

  private static String escape(String value) {
    StringBuilder out = new StringBuilder();
    for (int i = 0; i < value.length(); i++) {
      char ch = value.charAt(i);
      switch (ch) {
        case '"':
          out.append("\\\"");
          break;
        case '\\':
          out.append("\\\\");
          break;
        case '\b':
          out.append("\\b");
          break;
        case '\f':
          out.append("\\f");
          break;
        case '\n':
          out.append("\\n");
          break;
        case '\r':
          out.append("\\r");
          break;
        case '\t':
          out.append("\\t");
          break;
        default:
          if (ch < 0x20) {
            out.append(String.format("\\u%04x", (int) ch));
          } else {
            out.append(ch);
          }
      }
    }
    return out.toString();
  }
}
