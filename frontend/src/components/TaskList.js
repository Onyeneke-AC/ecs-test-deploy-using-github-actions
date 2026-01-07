import React from "react";
import "./TaskList.css";

function TaskList(props) {
  const tasks = Array.isArray(props.tasks) ? props.tasks : [];

  if (tasks.length === 0) {
    return <p>No tasks found.</p>;
  }

  return (
    <ul>
      {tasks.map((task) => (
        <li key={task.title}>
          <h2>{task.title}</h2>
          <p>{task.text}</p>
        </li>
      ))}
    </ul>
  );
}

export default TaskList;
